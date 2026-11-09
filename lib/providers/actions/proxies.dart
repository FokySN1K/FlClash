part of '../action.dart';

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
  });

  final String proxyName;
  final String testUrl;
  final String key;
}

typedef _DelayTestBatch = ({List<Proxy> proxies, String? testUrl});

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys, this.timeout) : held = keys.toSet();

  final Set<String> held;
  final Duration timeout;
  final Set<String> startedOnDispatch = {};
  bool cancelled = false;
}

/// A group's own check runs inside the Core, which reports the start and the
/// result of every probe it makes. The app holds only the group's own card for
/// the run: the members pulse from those reports, so a node shows a spinner
/// while it is really being measured instead of for the whole sweep.
class _GroupDelayTestJob {
  _GroupDelayTestJob(this.groupName) : held = {groupDelayTestKey(groupName)};

  final String groupName;

  /// The group's own card, held until the route it uses has a fresh value.
  final Set<String> held;

  /// The members whose values have landed in this run.
  final Set<String> settledMembers = {};

  void settleMember(String proxyName) {
    settledMembers.add(proxyName);
  }

  /// Releases the group's own card once its route has a fresh value.
  String? settleSelection() {
    final key = groupDelayTestKey(groupName);
    return held.remove(key) ? key : null;
  }
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  final TaskPool _delayTestPool = TaskPool(maxConcurrentDelayTests);

  final List<_DelayTestJob> _delayTestJobs = [];

  final List<_GroupDelayTestJob> _groupDelayTestJobs = [];

  final List<Delay> _bufferedDelays = [];

  final List<String> _bufferedStarts = [];

  final List<String> _bufferedFinishes = [];

  Timer? _delayFlushTimer;

  /// The pull that keeps a recovering pool's card in step with the Core.
  Timer? _recoveryRefreshTimer;

  bool _recoveringPullInFlight = false;

  /// The pull period of a recovering group. A test shortens it: waiting two
  /// seconds per pull is not something a suite can afford.
  Duration recoveryRefreshInterval = defaultRecoveryRefreshInterval;

  final Map<String, String> _pendingSelectedRollback = {};

  @override
  void build() {
    ref.onDispose(() {
      _delayFlushTimer?.cancel();
      _recoveryRefreshTimer?.cancel();
    });
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        cancelDelayTests();
        _cancelRecoveryRefresh();
      }
    });
  }

  /// A recovering pool keeps testing its nodes and re-decides the group's route
  /// inside the Core, but the card only learns that route by pulling again:
  /// without the pull it keeps showing the node that just died.
  void _syncRecoveryRefresh(List<Group> groups) {
    if (!groups.any((group) => group.recovering)) {
      _cancelRecoveryRefresh();
      return;
    }
    _recoveryRefreshTimer ??= Timer.periodic(
      recoveryRefreshInterval,
      (_) => _pullRecoveringGroups(),
    );
  }

  void _pullRecoveringGroups() {
    if (_recoveringPullInFlight) {
      return;
    }
    _recoveringPullInFlight = true;
    updateGroups().whenComplete(() => _recoveringPullInFlight = false);
  }

  void _cancelRecoveryRefresh() {
    _recoveryRefreshTimer?.cancel();
    _recoveryRefreshTimer = null;
  }

  void cancelDelayTests() {
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      job.held.clear();
    }
    _groupDelayTestJobs.clear();
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    _bufferedDelays.clear();
    _bufferedStarts.clear();
    _bufferedFinishes.clear();
    ref.read(pendingDelayTestsProvider.notifier).clear();
    // The checks the frozen set waits for are exactly the ones that just died,
    // so no end will ever unfreeze their groups.
    ref.read(delayTestingGroupsProvider.notifier).reset();
  }

  void _scheduleDelayFlush() {
    _delayFlushTimer ??= Timer(renderThrottleDuration, _flushDelayResults);
  }

  void _flushDelayResults() {
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    final settled = <String>{};
    if (_bufferedDelays.isNotEmpty) {
      final delays = List.of(_bufferedDelays);
      _bufferedDelays.clear();
      // The value lands first, so a card that drops its spinner in the same
      // frame already shows the number it was waiting for.
      ref.read(delayDataSourceProvider.notifier).setDelays(delays);
      for (final job in _groupDelayTestJobs) {
        for (final delay in delays) {
          job.settleMember(delay.name);
        }
        if (_groupSelectionSettled(job)) {
          final own = job.settleSelection();
          if (own != null) {
            settled.add(own);
          }
        }
      }
    }
    if (_bufferedStarts.isNotEmpty ||
        _bufferedFinishes.isNotEmpty ||
        settled.isNotEmpty) {
      final started = List.of(_bufferedStarts);
      final finished = List.of(_bufferedFinishes)..addAll(settled);
      _bufferedStarts.clear();
      _bufferedFinishes.clear();
      ref
          .read(pendingDelayTestsProvider.notifier)
          .apply(started: started, finished: finished);
    }
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    _pendingSelectedRollback.putIfAbsent(
      groupName,
      () => _currentSelectedName(groupName),
    );
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
    debouncer.call((FunctionTag.changeProxy, groupName), (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  String _currentSelectedName(String groupName) {
    return ref.read(currentProfileProvider)?.selectedMap[groupName] ?? '';
  }

  Future<void> updateGroups() async {
    try {
      final List<Group> groups = await retry(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            patchClashConfigProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          try {
            return await _core.getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            );
          } catch (e) {
            commonPrint.log(
              'updateGroups error: $e',
              logLevel: coreFailureLogLevel(e),
            );
            return [];
          }
        },
        retryIf: (res) => res.isEmpty,
      );
      // A group under test keeps the order the page already shows: its results
      // land one at a time, so the sort that follows every one of them would
      // otherwise move a card out from under the cursor.
      ref.read(groupsProvider.notifier).value = keepTestedGroupOrder(
        previous: ref.read(groupsProvider),
        next: groups,
        frozen: ref.read(delayTestingGroupsProvider),
      );
      _syncRecoveryRefresh(groups);
    } catch (e) {
      // The Core failure path already runs inside the retry task above; a
      // throw here only means ref.read hit a disposed container or the
      // groupsProvider write itself failed.
      commonPrint.log(
        'updateGroups failed: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(pendingDelayTestsProvider.notifier).probeAnswered(delay.name);
    _bufferedDelays.add(delay);
    _scheduleDelayFlush();
  }

  /// The Core reports the start of every probe it runs, so a node pulses while
  /// it is really measured instead of for the whole check it belongs to.
  void onDelayStart(Delay delay) {
    ref.read(pendingDelayTestsProvider.notifier).probeStarted(delay.name);
  }

  /// The Core has begun a check of its own. Its members queue with the value
  /// they already had, and the group keeps its card order until it is over.
  void onCheckStart({
    required String group,
    required String url,
    required List<String> names,
  }) {
    final testUrl = url.takeFirstValid([
      ref.read(groupsProvider).getGroup(group)?.testUrl,
      ref.read(patchClashConfigProvider.select((state) => state.testUrl)),
    ]);
    ref
        .read(pendingDelayTestsProvider.notifier)
        .coreCheckStarted(group: group, url: testUrl, names: names);
    ref.read(delayTestingGroupsProvider.notifier).coreStarted(group);
  }

  /// The check is over and the Core has re-decided the group's route, so the
  /// page pulls it now instead of leaving the tick on a node that timed out
  /// until the delay debounce expires.
  void onCheckEnd({required String group}) {
    ref.read(pendingDelayTestsProvider.notifier).coreCheckEnded(group: group);
    ref.read(delayTestingGroupsProvider.notifier).coreEnded(group);
    _refreshAfterDelayTest();
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final rollbackName =
        _pendingSelectedRollback.remove(groupName) ??
        _currentSelectedName(groupName);
    profilesAction.updateCurrentSelectedMap(groupName, proxyName);
    final ChangeProxyResult result;
    try {
      result = await _core.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      );
      if (result.message.isNotEmpty) {
        throw MessageException(result.message);
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
      profilesAction.updateCurrentSelectedMap(groupName, rollbackName);
      dialogs.showNotifier(
        currentAppLocalizations.changeProxyFailedTip,
        level: MessageLevel.error,
      );
      return;
    }
    if (!result.changed) {
      return;
    }
    try {
      if (ref.read(appSettingProvider).closeConnections) {
        await _core.closeConnections();
      } else {
        await _core.resetConnections();
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) connection reset failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final clashProvidersAction = ref.read(
        clashProvidersActionProvider.notifier,
      );
      final ruleSet = await clashProvidersAction.remoteProviderOf(provider);
      if (ruleSet != null && !await clashProvidersAction.syncRemote(ruleSet)) {
        return '';
      }
      final message = await _core.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<String> sideLoadExternalProvider(
    ExternalProvider provider,
    String data, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final message = await _core.sideLoadExternalProvider(
        providerName: provider.name,
        data: data,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> addToLocalProxies(String proxyName) async {
    final appLocalizations = currentAppLocalizations;
    final definition = await _core.getProxyDefinition(proxyName);
    if (definition == null) {
      throw MessageException(
        appLocalizations.customIssueMissingProxies(proxyName),
      );
    }
    final (proxies, groupNames) = await (
      database.customProxiesDao.query().get(),
      database.proxyGroupsDao.names().get(),
    ).wait;
    final (:name, :added) = importProxy(
      definition,
      existing: [for (final proxy in proxies) proxy.definition],
      groupNames: groupNames.toSet(),
    );
    if (added == null) {
      dialogs.showNotifier(appLocalizations.alreadyInLocalProxies(name));
      return;
    }
    final order = indexing.generateKeyBetween(
      proxies.map((proxy) => proxy.order).nonNulls.lastOrNull,
      null,
    );
    await database.customProxies.put(
      CustomProxy.fromDefinition(added).copyWith(order: order).toCompanion(),
    );
    dialogs.showNotifier(appLocalizations.addedToLocalProxies(name));
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
    final group = _selfTestedGroupOf(proxy);
    if (group != null) {
      await _runGroupDelayTest(group);
      _refreshAfterDelayTest(resort: false);
      return;
    }
    await _runDelayTests([
      (proxies: [proxy], testUrl: testUrl),
    ]);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests([(proxies: proxies, testUrl: testUrl)]);
    _refreshAfterDelayTest();
  }

  /// A run from the tray menu or a hotkey measures every group at once, so
  /// each of them keeps its cards in place until the run is over: the results
  /// land one at a time, and a sort after each of them would move the list
  /// while the numbers are still arriving.
  Future<void> delayTestGroups(List<Group> groups) async {
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    final started = <String>{};
    for (final group in groups) {
      if (testing.start(group.name)) {
        started.add(group.name);
      }
    }
    try {
      await Future.wait([
        // A pool or an ordered fallback measures its own members inside the
        // Core's check, so probing them here again would race that check.
        _runDelayTests([
          for (final group in groups)
            if (!group.type.isSelfTested)
              (proxies: group.all, testUrl: group.testUrl),
        ]),
        Future.wait([for (final group in groups) _runGroupDelayTest(group)]),
      ]);
    } finally {
      for (final name in started) {
        testing.stop(name);
      }
    }
    _refreshAfterDelayTest();
  }

  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null) {
      return;
    }
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    if (!testing.start(groupName)) {
      return;
    }
    try {
      final query = SearchQuery(
        matchSearch ? ref.read(queryProvider(QueryTag.proxies)) : '',
      );
      await Future.wait([
        if (!group.type.isSelfTested)
          _runDelayTests([
            (
              proxies: group.all
                  .whereMatches(query, (proxy) => proxy.searchFields)
                  .toList(),
              testUrl: group.testUrl,
            ),
          ]),
        _runGroupDelayTest(group),
      ]);
    } finally {
      testing.stop(groupName);
    }
    _refreshAfterDelayTest();
  }

  Group? _selfTestedGroupOf(Proxy proxy) {
    final groupType = GroupTypeExtension.getGroupType(proxy.type);
    if (groupType == null || !groupType.isSelfTested) {
      return null;
    }
    return ref.read(groupsProvider).getGroup(proxy.name);
  }

  /// A pool and an ordered fallback re-decide their route only in their own
  /// check, which the Core runs here against the group's own target; the
  /// members it measures arrive as delay messages on their own, and each of
  /// them pulses from the probe the Core reports it started.
  Future<void> _runGroupDelayTest(Group group) async {
    if (!group.type.isSelfTested) {
      return;
    }
    final job = _GroupDelayTestJob(group.name);
    _groupDelayTestJobs.add(job);
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    pending.apply(acquired: job.held, started: job.held);
    try {
      final delay = await _core.getGroupDelay(
        group.name,
        Duration(milliseconds: ref.read(appSettingProvider).delayTestTimeout),
      );
      if (delay != null) {
        setDelay(delay);
      }
    } catch (error) {
      commonPrint.log(
        'Group delay test failed for ${group.name}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      _groupDelayTestJobs.remove(job);
      _flushDelayResults();
      final abandoned = job.held.toList();
      job.held.clear();
      pending.apply(finished: abandoned);
    }
  }

  /// Whether the member the group routes to has answered in this run, which is
  /// what lets the group's own card show a number instead of a spinner.
  bool _groupSelectionSettled(_GroupDelayTestJob job) {
    final state = computeRealSelectedProxyState(
      job.groupName,
      groups: ref.read(groupsProvider),
      selectedMap: ref.read(
        currentProfileProvider.select((state) => state?.selectedMap ?? {}),
      ),
    );
    return job.settledMembers.contains(state.proxyName);
  }

  /// Results stream in while a test runs, so the groups are pulled once it
  /// ends instead of waiting for the debounce those messages schedule.
  void _refreshAfterDelayTest({bool resort = true}) {
    _flushDelayResults();
    if (resort) {
      ref.read(sortNumProvider.notifier).add();
    }
    updateGroupsDebounce(renderThrottleDuration);
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<_DelayTestBatch> batches,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final batch in batches) {
      final fallbackTestUrl = ref.read(realTestUrlProvider(batch.testUrl));
      for (final proxy in batch.proxies) {
        final state = computeRealSelectedProxyState(
          proxy.name,
          groups: groups,
          selectedMap: selectedMap,
        );
        if (state.proxyName.isEmpty) {
          continue;
        }
        final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
        final key = delayTestKey(currentTestUrl, state.proxyName);
        if (!seen.add(key)) {
          continue;
        }
        targets.add(
          _DelayTestTarget(
            proxyName: state.proxyName,
            testUrl: currentTestUrl,
            key: key,
          ),
        );
      }
    }
    return targets;
  }

  Future<void> _runDelayTests(List<_DelayTestBatch> batches) async {
    final targets = _resolveDelayTestTargets(batches);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(
      targets.map((target) => target.key),
      Duration(milliseconds: ref.read(appSettingProvider).delayTestTimeout),
    );
    _delayTestJobs.add(job);
    // TaskPool.run starts a task synchronously while it has an idle slot.
    job.startedOnDispatch.addAll(
      targets.take(_delayTestPool.idleSlots).map((target) => target.key),
    );
    pending.apply(acquired: job.held, started: job.startedOnDispatch);
    try {
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      _flushDelayResults();
      final abandoned = job.held.toList();
      job.held.clear();
      pending.apply(
        finished: abandoned.where(job.startedOnDispatch.contains),
        released: abandoned.where(
          (key) => !job.startedOnDispatch.contains(key),
        ),
      );
    }
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    if (!job.startedOnDispatch.contains(target.key)) {
      _bufferedStarts.add(target.key);
      _scheduleDelayFlush();
    }
    try {
      final delay = await _core.getDelay(
        target.testUrl,
        target.proxyName,
        job.timeout,
      );
      if (delay != null && !job.cancelled) {
        setDelay(delay);
      }
    } catch (error) {
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      if (job.held.remove(target.key)) {
        _bufferedFinishes.add(target.key);
        _scheduleDelayFlush();
      }
    }
  }
}
