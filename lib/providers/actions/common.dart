part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  /// The check the About page and the tools list share: the automatic request
  /// with the "already current" answer the background run leaves silent.
  Future<void> checkUpdate({bool isUser = false}) async {
    final result = await globalState.loadingRun(
      () async => (release: await request.checkForUpdate()),
      title: currentAppLocalizations.checkUpdate,
      tag: LoadingTag.checkUpdate,
    );
    if (result == null) return;
    await checkUpdateResultHandle(data: result.release, isUser: isUser);
  }

  /// Downloads the archive this build can install without blocking the page
  /// that asked for it; the end of the transfer turns into an install action.
  /// A release that never built for this platform keeps the release page as
  /// the way to its download.
  Future<void> downloadRelease(Map<String, dynamic> release) async {
    final asset = releaseAsset(release);
    if (asset == null) {
      _openReleasePage(release);
      return;
    }
    final file = await ref
        .read(releaseDownloadProvider.notifier)
        .run(asset, version: _releaseVersion(release));
    if (file == null) return;
    _offerInstall(release);
  }

  /// Installs [release], waiting for a transfer that is still running.
  Future<void> installRelease(Map<String, dynamic> release) async {
    final asset = releaseAsset(release);
    if (asset == null) {
      _openReleasePage(release);
      return;
    }
    final download = ref.read(releaseDownloadProvider.notifier);
    final file =
        await download.readyFile(asset) ??
        await download.run(asset, version: _releaseVersion(release));
    if (file == null) return;
    await _installArchive(file);
  }

  /// Installs the archive the last finished download left on disk.
  Future<void> installReadyRelease() async {
    final file = ref.read(releaseDownloadProvider.notifier).readyArchive;
    if (file == null || !await file.exists()) return;
    await _installArchive(file);
  }

  /// Offers the finished archive as a floating action that waits for the user
  /// instead of expiring with a regular toast.
  void _offerInstall(Map<String, dynamic> release) {
    final localizations = currentAppLocalizations;
    dialogs.showNotifier(
      localizations.updateReady,
      level: MessageLevel.success,
      actionState: MessageActionState(
        actionText: localizations.installNow,
        action: () => unawaited(installRelease(release)),
      ),
      duration: Duration.zero,
    );
  }

  void _openReleasePage(Map<String, dynamic> release) {
    final tagName = release['tag_name'];
    commonPrint.log(
      'no ${releaseAssetSuffix()} archive in release $tagName',
      logLevel: LogLevel.warning,
    );
    unawaited(
      launchUrl(Uri.parse('https://github.com/$repository/releases/latest')),
    );
  }

  Future<void> _installArchive(File file) async {
    final handedOff = await globalState.safeRun(
      () => launchReleaseAsset(file),
      title: currentAppLocalizations.update,
    );
    if (handedOff != true) return;
    await ref.read(systemActionProvider.notifier).handleExit();
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      if (!isUser && ref.read(appSettingProvider).autoDownloadUpdate) {
        unawaited(downloadRelease(data));
      }
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        unawaited(downloadRelease(data));
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}

String? _releaseVersion(Map<String, dynamic> release) {
  final tag = release['tag_name'];
  return tag is String ? tag : null;
}
