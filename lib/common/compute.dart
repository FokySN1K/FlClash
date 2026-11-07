import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

List<Group> computeSort({
  required List<Group> groups,
  required ProxiesSortType sortType,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  List<Proxy> sortOfDelay({
    required List<Group> groups,
    required List<Proxy> proxies,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String testUrl,
  }) {
    final delayStates = {
      for (final proxy in proxies)
        proxy.name: computeProxyDelayState(
          proxyName: proxy.name,
          testUrl: testUrl,
          groups: groups,
          selectedMap: selectedMap,
          delayMap: delayMap,
        ),
    };
    return List.of(proxies)
      ..sort((a, b) => delayStates[a.name]!.compareTo(delayStates[b.name]!));
  }

  List<Proxy> sortOfName(List<Proxy> proxies) {
    return List.of(proxies)..sort((a, b) => a.name.compareTo(b.name));
  }

  // A selector keeps the groups the profile put among its members where they
  // are and sorts only the nodes into the places that are left.
  List<Proxy> sortSelectorOfDelay({
    required List<Group> groups,
    required List<Proxy> proxies,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String testUrl,
  }) {
    final groupNames = {for (final group in groups) group.name};
    final sorted = sortOfDelay(
      groups: groups,
      proxies: [
        for (final proxy in proxies)
          if (!groupNames.contains(proxy.name)) proxy,
      ],
      delayMap: delayMap,
      selectedMap: selectedMap,
      testUrl: testUrl,
    );
    var next = 0;
    return [
      for (final proxy in proxies)
        if (groupNames.contains(proxy.name)) proxy else sorted[next++],
    ];
  }

  return groups.map((group) {
    final proxies = group.all;
    final testUrl = group.testUrl.takeFirstValid([defaultTestUrl]);
    final newProxies = switch (sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => switch (group.type) {
        GroupType.Selector => sortSelectorOfDelay(
          groups: groups,
          proxies: proxies,
          delayMap: delayMap,
          selectedMap: selectedMap,
          testUrl: testUrl,
        ),
        _ => sortOfDelay(
          groups: groups,
          proxies: proxies,
          delayMap: delayMap,
          selectedMap: selectedMap,
          testUrl: testUrl,
        ),
      },
      ProxiesSortType.name => sortOfName(proxies),
    };
    return group.copyWith(all: newProxies);
  }).toList();
}

/// Keeps the members of a group a check is running in the order the page
/// already shows them. A sweep lands one result at a time, and a list that
/// re-sorted on each of them would move a card out from under the cursor. A
/// member the group did not have keeps the place the Core gave it.
List<Group> keepTestedGroupOrder({
  required List<Group> previous,
  required List<Group> next,
  required Set<String> frozen,
}) {
  if (frozen.isEmpty || previous.isEmpty) {
    return next;
  }
  final previousMembers = {
    for (final group in previous) group.name: group.all,
  };
  return [
    for (final group in next)
      if (frozen.contains(group.name))
        group.copyWith(
          all: _keepMemberOrder(group.all, previousMembers[group.name]),
        )
      else
        group,
  ];
}

List<Proxy> _keepMemberOrder(List<Proxy> members, List<Proxy>? previous) {
  if (previous == null || previous.isEmpty) {
    return members;
  }
  final byName = {for (final member in members) member.name: member};
  final ordered = <Proxy>[];
  for (final member in previous) {
    final current = byName.remove(member.name);
    if (current != null) {
      ordered.add(current);
    }
  }
  for (final member in members) {
    final current = byName.remove(member.name);
    if (current != null) {
      ordered.add(current);
    }
  }
  return ordered;
}

/// Built-in adapters whose delay probe always fails, so a timeout says nothing.
const _unprobeableProxyTypes = {
  'Reject',
  'RejectDrop',
  'Pass',
  'PassRule',
  'Rematch',
  'Compatible',
  'Dns',
};

List<Group> computeHideTimeout({
  required List<Group> groups,
  required List<Group> allGroups,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
  Set<String> frozen = const {},
}) {
  final realStates = <String, SelectedProxyState>{};
  final proxyTypes = {
    for (final group in allGroups)
      for (final proxy in group.all) proxy.name: proxy.type,
  };
  return groups.map((group) {
    // A group under test keeps every member: a node that just timed out may
    // answer on the next check, and dropping it would shuffle the list under
    // the cursor while the cards are being measured.
    if (frozen.contains(group.name)) {
      return group;
    }
    final groupTestUrl = group.testUrl.takeFirstValid([defaultTestUrl]);
    final groupWithNow = allGroups.getGroup(group.name) ?? group;
    final selectedName = groupWithNow.getCurrentSelectedName(
      selectedMap[group.name] ?? '',
    );
    final visible = group.all.where((proxy) {
      // A group's delay is its pick's, and hiding it would take away the only
      // way to choose the group where the mode does not show it on its own.
      if (proxy.name == selectedName ||
          allGroups.getGroup(proxy.name) != null) {
        return true;
      }
      final state = realStates.putIfAbsent(
        proxy.name,
        () => computeRealSelectedProxyState(
          proxy.name,
          groups: allGroups,
          selectedMap: selectedMap,
        ),
      );
      if (_unprobeableProxyTypes.contains(proxyTypes[state.proxyName])) {
        return true;
      }
      final testUrl = state.testUrl.takeFirstValid([groupTestUrl]);
      final delay = delayMap[testUrl]?[state.proxyName];
      return delay == null || delay > 0;
    }).toList();
    return group.copyWith(all: visible.isEmpty ? group.all : visible);
  }).toList();
}

SelectedProxyState getRealSelectedProxyState(
  SelectedProxyState state, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  if (state.proxyName.isEmpty) return state;
  final group = groups.getGroup(state.proxyName);
  final newState = state.copyWith(group: true);
  if (group == null) return newState;
  final currentSelectedName = group.getCurrentSelectedName(
    selectedMap[newState.proxyName] ?? '',
  );
  if (currentSelectedName.isEmpty) {
    return newState;
  }
  return getRealSelectedProxyState(
    newState.copyWith(proxyName: currentSelectedName, testUrl: group.testUrl),
    groups: groups,
    selectedMap: selectedMap,
  );
}

SelectedProxyState computeRealSelectedProxyState(
  String proxyName, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  return getRealSelectedProxyState(
    SelectedProxyState(proxyName: proxyName),
    groups: groups,
    selectedMap: selectedMap,
  );
}

/// Marks a key filed under a group rather than under the page that shows the
/// card; no test URL or proxy name starts with it.
const _groupScopeMarker = '\u0001';

/// A delay test files what it measures under the URL it runs against. A group
/// check adds its own name to the key, so the same node in a group that did
/// not run the check can tell the two apart.
String delayTestKey(String testUrl, String proxyName, {String? groupName}) {
  final node = '$testUrl\u0000$proxyName';
  if (groupName == null) {
    return node;
  }
  return '$_groupScopeMarker$groupName\u0000$node';
}

/// The key a group's own check is filed under, whatever target it runs, so the
/// card that started the check finds it from the name alone.
String groupDelayTestKey(String groupName) {
  return '$_groupScopeMarker$groupName';
}

/// Marks a node the Core reported as being probed right now. It is filed by the
/// name alone: a pulse says the node is being measured, not which target or
/// group started the check, and a card cannot know the target a group's own
/// check runs.
const _coreProbeMarker = '\u0002';

String coreProbeKey(String proxyName) => '$_coreProbeMarker$proxyName';

DelayState computeProxyDelayState({
  required String proxyName,
  required String testUrl,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  required DelayMap delayMap,
}) {
  final state = computeRealSelectedProxyState(
    proxyName,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentDelayMap =
      delayMap[state.testUrl.takeFirstValid([testUrl])] ?? {};
  final delay = currentDelayMap[state.proxyName];
  return DelayState(delay: delay ?? 0, group: state.group);
}
