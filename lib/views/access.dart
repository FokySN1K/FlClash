import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The apps the tunnel carries. The mode picks the list a manual mark writes,
/// the profile's own `PROCESS-NAME*` rules stand beside it, and a manual mark
/// always beats the rule. The whitelist picks its apps on its own, so the
/// profile's marks stay hidden there.
class AccessView extends ConsumerStatefulWidget {
  const AccessView({super.key});

  @override
  ConsumerState<AccessView> createState() => _AccessViewState();
}

class _AccessViewState extends ConsumerState<AccessView>
    with RouteSettledMixin<AccessView> {
  late ScrollController _controller;
  bool _installedAppsPermissionGranted = true;

  final _completer = Completer();

  /// The manual marks the screen opened with: a tap changes the marks, but the
  /// rows keep the order they were found in, so the row under the finger does
  /// not run away.
  late final AccessControlProps _orderMarks;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
    _orderMarks = ref.read(accessControlStateProvider);
    _completer.complete(_loadPackages());
  }

  @override
  void didSettleRoute() => setState(() {});

  Future<void> _loadPackages() async {
    final action = ref.read(systemActionProvider.notifier);
    final packages = await action.getPackages();
    final granted =
        packages.isNotEmpty || await action.isInstalledAppsPermissionGranted();
    if (!mounted || granted == _installedAppsPermissionGranted) {
      return;
    }
    setState(() {
      _installedAppsPermissionGranted = granted;
    });
  }

  Future<void> _handleGrantInstalledAppsPermission() async {
    final appLocalizations = context.appLocalizations;
    final granted = await ref
        .read(systemActionProvider.notifier)
        .requestInstalledAppsPermission();
    if (!mounted) {
      return;
    }
    if (!granted) {
      final res = await dialogs.showMessage(
        message: TextSpan(
          text: appLocalizations.installedAppsPermissionDeniedMessage,
        ),
        confirmText: appLocalizations.settings,
      );
      if (res == true) {
        await app?.openAppSettings();
      }
      return;
    }
    await globalState.loadingRun(_loadPackages, tag: LoadingTag.access);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconButtonData _buildSelectAllAction({
    required bool isSelectedAll,
    required List<String> allValueList,
  }) {
    void onPressed() {
      ref.read(accessControlStateProvider.notifier).update((state) {
        final current = Set<String>.from(state.currentList);
        final other = Set<String>.from(state.otherList);
        final isSelectedAll = current.containsAll(allValueList);
        if (isSelectedAll) {
          current.removeAll(allValueList);
        } else {
          current.addAll(allValueList);
          other.removeAll(allValueList);
        }
        return state.copyWithNewLists(current.toList(), other.toList());
      });
    }

    final appLocalizations = context.appLocalizations;
    return isSelectedAll
        ? IconButtonData(
            glyph: AppGlyphs.deselect,
            tooltip: appLocalizations.cancelSelectAll,
            onPressed: onPressed,
          )
        : IconButtonData(
            glyph: AppGlyphs.selectAll,
            tooltip: appLocalizations.selectAll,
            onPressed: onPressed,
          );
  }

  Future<void> _intelligentSelected() async {
    final packageNames = ref.read(
      packagesProvider.select((state) => state.map((item) => item.packageName)),
    );
    if (packageNames.isEmpty) {
      return;
    }
    final selectedPackageNames =
        (await globalState.loadingRun<List<String>>(() async {
          return await app?.getChinaPackageNames() ?? [];
        }, tag: LoadingTag.access))?.toSet() ??
        {};
    final acceptList = packageNames
        .where((item) => !selectedPackageNames.contains(item))
        .toList();
    final rejectList = packageNames
        .where((item) => selectedPackageNames.contains(item))
        .toList();
    ref
        .read(accessControlStateProvider.notifier)
        .update(
          (state) =>
              state.copyWith(acceptList: acceptList, rejectList: rejectList),
        );
  }

  /// The manual mark: checked is the mode's own list, empty the opposite one,
  /// a dash means no choice at all.
  bool? _manualState(String packageName, AccessControlProps accessControl) {
    if (accessControl.currentList.contains(packageName)) {
      return true;
    }
    if (accessControl.otherList.contains(packageName)) {
      return false;
    }
    return null;
  }

  /// No choice -> the mode's list -> the opposite list -> no choice.
  void _cycleManual(String packageName) {
    ref.read(accessControlStateProvider.notifier).update((state) {
      final current = Set<String>.from(state.currentList);
      final other = Set<String>.from(state.otherList);
      switch (_manualState(packageName, state)) {
        case null:
          current.add(packageName);
          other.remove(packageName);
        case true:
          current.remove(packageName);
          other.add(packageName);
        case false:
          other.remove(packageName);
      }
      return state.copyWithNewLists(current.toList(), other.toList());
    });
  }

  /// Where the profile's own rule sends the app, or null when no
  /// `PROCESS-NAME*` rule covers it. The ignore switch and the whitelist pass
  /// no rules, so the column disappears there.
  String? _profileTarget(String packageName, ProcessRules processRules) =>
      processRules.targetFor(packageName);

  int _rank(
    String packageName,
    AccessControlProps orderMarks,
    ProcessRules processRules,
  ) {
    if (_manualState(packageName, orderMarks) != null) {
      return 0;
    }
    if (_profileTarget(packageName, processRules) != null) {
      return 1;
    }
    return 2;
  }

  /// The manual marks the screen opened with come first, then the apps the
  /// profile names, then the rest; inside a rank the chosen sort holds. A tap
  /// changes the live marks, never [orderMarks], so no row moves under it.
  List<Package> _ranked(
    List<Package> packages,
    AccessControlProps orderMarks,
    ProcessRules processRules,
  ) {
    final byRank = <int, List<Package>>{};
    for (final package in packages) {
      final rank = _rank(package.packageName, orderMarks, processRules);
      byRank.putIfAbsent(rank, () => []).add(package);
    }
    return [
      for (final rank in const [0, 1, 2]) ...?byRank[rank],
    ];
  }

  void _update(AccessControlProps Function(AccessControlProps state) update) {
    ref.read(accessControlStateProvider.notifier).update(update);
  }

  Future<void> _handleBack() async {
    final res = await dialogs.showSaveChanges();
    if (res == null) {
      return;
    }
    if (res) {
      _handleSave();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  AccessControlProps _getRealAccessControlProps(
    AccessControlProps accessControl,
  ) {
    final packages = ref.read(packagesProvider);
    if (packages.isEmpty) {
      return accessControl;
    }
    final viewPackageNames = packages
        .whereVisible(
          isFilterSystemApp: accessControl.isFilterSystemApp,
          isFilterNonInternetApp: accessControl.isFilterNonInternetApp,
        )
        .map((item) => item.packageName)
        .toSet();
    return accessControl.copyWithNewList(
      accessControl.currentList
          .where((item) => viewPackageNames.contains(item))
          .toList()
        ..sort(),
    );
  }

  /// The tunnel options read the exclusion lists on their own, so the saved
  /// marks are mirrored there as well.
  void _handleSave() {
    final accessControl = _getRealAccessControlProps(
      ref.read(accessControlStateProvider),
    );
    ref
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            accessControlProps: accessControl,
            excludePackages: [...accessControl.rejectList]..sort(),
            includePackages: [...accessControl.acceptList]..sort(),
          ),
        );
  }

  Future<void> _exportToClipboard() async {
    await globalState.safeRun(() {
      final currentList = ref.read(
        accessControlStateProvider.select((state) => state.currentList),
      );
      Clipboard.setData(ClipboardData(text: currentList.join('\n')));
    });
  }

  Future<void> _importFormClipboard() async {
    await globalState.safeRun(() async {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text == null) return;
      final list = text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      ref
          .read(accessControlStateProvider.notifier)
          .update(
            (state) => state.copyWithNewLists(
              list.toList(),
              state.otherList.where((item) => !list.contains(item)).toList(),
            ),
          );
    });
  }

  Future<void> _showLegend() async {
    final appLocalizations = context.appLocalizations;
    final accessControl = ref.read(accessControlStateProvider);
    final ignored = ref.read(vpnSettingProvider).ignoreProfileProcessRules;
    final whitelist = accessControl.mode == AccessControlMode.acceptSelected;
    await dialogs.showMessage(
      message: TextSpan(
        text: [
          appLocalizations.accessControlMarkHint,
          if (whitelist)
            appLocalizations.vpnExclusionsWhitelistMode
          else if (ignored)
            appLocalizations.ignoreProfileProcessRulesDesc
          else
            appLocalizations.vpnExclusionsProfileHint,
          appLocalizations.vpnExclusionsLockdown,
        ].join('\n\n'),
      ),
    );
  }

  List<CommonPopupMenuItem> _buildMenuItems(
    BuildContext context,
    AccessControlProps accessControl,
    VpnProps vpnSetting,
  ) {
    final appLocalizations = context.appLocalizations;
    String modeText(AccessControlMode mode) => switch (mode) {
      AccessControlMode.acceptSelected => appLocalizations.whitelistMode,
      AccessControlMode.rejectSelected => appLocalizations.blacklistMode,
    };
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.toggleOn,
        label: appLocalizations.turnOn,
        checked: accessControl.enable,
        section: CommonPopupMenuSection(title: appLocalizations.accessControl),
        onPressed: () => _update((state) => state.copyWith(enable: true)),
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.toggle,
        label: appLocalizations.turnOff,
        checked: !accessControl.enable,
        onPressed: () => _update((state) => state.copyWith(enable: false)),
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.sliders,
        label: appLocalizations.settings,
        subtitle: modeText(accessControl.mode),
        section: const CommonPopupMenuSection(),
        subItems: [
          ..._optionsSection(
            title: appLocalizations.mode,
            options: AccessControlMode.values,
            value: accessControl.mode,
            textOf: modeText,
            onSelected: (mode) =>
                _update((state) => state.copyWith(mode: mode)),
          ),
          ..._optionsSection(
            title: appLocalizations.sort,
            options: AccessSortType.values,
            value: accessControl.sort,
            textOf: (type) => switch (type) {
              AccessSortType.none => appLocalizations.defaultText,
              AccessSortType.name => appLocalizations.name,
              AccessSortType.time => appLocalizations.time,
            },
            onSelected: (sort) =>
                _update((state) => state.copyWith(sort: sort)),
          ),
          CommonPopupMenuItem(
            label: appLocalizations.systemApp,
            checked: !accessControl.isFilterSystemApp,
            section: CommonPopupMenuSection(title: appLocalizations.source),
            onPressed: () => _update(
              (state) =>
                  state.copyWith(isFilterSystemApp: !state.isFilterSystemApp),
            ),
          ),
          CommonPopupMenuItem(
            label: appLocalizations.noNetworkApp,
            checked: !accessControl.isFilterNonInternetApp,
            onPressed: () => _update(
              (state) => state.copyWith(
                isFilterNonInternetApp: !state.isFilterNonInternetApp,
              ),
            ),
          ),
          if (accessControl.mode != AccessControlMode.acceptSelected)
            CommonPopupMenuItem(
              label: appLocalizations.ignoreProfileProcessRules,
              checked: vpnSetting.ignoreProfileProcessRules,
              section: CommonPopupMenuSection(title: appLocalizations.profile),
              onPressed: () => ref
                  .read(vpnSettingProvider.notifier)
                  .update(
                    (state) => state.copyWith(
                      ignoreProfileProcessRules:
                          !state.ignoreProfileProcessRules,
                    ),
                  ),
            ),
        ],
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.moreCircle,
        label: appLocalizations.action,
        subItems: [
          CommonPopupMenuItem(
            glyph: AppGlyphs.sparkle,
            label: appLocalizations.intelligentSelected,
            onPressed: _intelligentSelected,
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.copy,
            label: appLocalizations.clipboardExport,
            onPressed: _exportToClipboard,
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.paste,
            label: appLocalizations.clipboardImport,
            onPressed: _importFormClipboard,
          ),
        ],
      ),
    ];
  }

  Widget _buildContent({
    required List<Package> packages,
    required AccessControlProps accessControl,
    required ProcessRules processRules,
    required bool showProfile,
    required bool isSearching,
  }) {
    return FutureBuilder(
      future: _completer.future,
      builder: (context, snapshot) {
        final appLocalizations = context.appLocalizations;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CommonCircleLoading.page());
        }
        return NullStatusSwitcher(
          isEmpty: packages.isEmpty,
          isSearching: isSearching,
          nullStatus: NullStatus(
            label: appLocalizations.noData,
            illustration: NullStatusIllustration.apps,
          ),
          child: CommonScrollBar(
            controller: _controller,
            child: ListView.builder(
              controller: _controller,
              padding: EdgeInsets.only(
                top: context.contentTopPadding,
                bottom: context.bottomInset,
              ),
              scrollCacheExtent: arrivalScrollCacheExtent(routeSettled),
              itemCount: packages.length,
              itemExtent: 72,
              itemBuilder: (_, index) {
                final package = packages[index];
                return PackageListItem(
                  key: Key(package.packageName),
                  package: package,
                  value: _manualState(package.packageName, accessControl),
                  profileTarget: _profileTarget(
                    package.packageName,
                    processRules,
                  ),
                  showProfile: showProfile,
                  onChanged: () => _cycleManual(package.packageName),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstalledAppsPermissionStatus() {
    final appLocalizations = context.appLocalizations;
    return NullStatus(
      label: appLocalizations.installedAppsPermissionRequired,
      description: appLocalizations.installedAppsPermissionDesc,
      illustration: NullStatusIllustration.permission,
      action: TonalButton(
        size: TonalButtonSize.bar,
        glyph: AppGlyphs.lockOpen,
        label: appLocalizations.authorize,
        onPressed: _handleGrantInstalledAppsPermission,
      ),
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.access).notifier).value = value;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final isLoading = ref.watch(loadingProvider(LoadingTag.access));
    final query = SearchQuery(ref.watch(queryProvider(QueryTag.access)));
    final packages = ref.watch(packagesProvider);
    final accessControl = ref.watch(accessControlStateProvider);
    final vpnSetting = ref.watch(vpnSettingProvider);
    // The whitelist picks its apps on its own, and ignored profile rules must
    // not rank or tick the apps either.
    final showProfile = accessControl.mode != AccessControlMode.acceptSelected;
    final profileRules = ref.watch(profileProcessRulesProvider);
    final processRules = !showProfile || vpnSetting.ignoreProfileProcessRules
        ? const ProcessRules.empty()
        : profileRules;
    final searchedPackages = packages
        .getViewList(
          pinedList: const [],
          sortType: accessControl.sort,
          isFilterNonInternetApp: accessControl.isFilterNonInternetApp,
          isFilterSystemApp: accessControl.isFilterSystemApp,
        )
        .whereMatches(query, (package) => [package.label, package.packageName])
        .toList();
    final viewPackages = _ranked(searchedPackages, _orderMarks, processRules);
    final currentList = accessControl.currentList;
    final viewPackageNameList = viewPackages.map((e) => e.packageName).toList();
    final valueList = currentList.intersection(viewPackageNameList);
    final needsInstalledAppsPermission =
        packages.isEmpty && !_installedAppsPermissionGranted;
    final selectAllAction =
        !needsInstalledAppsPermission && viewPackageNameList.isNotEmpty
        ? _buildSelectAllAction(
            isSelectedAll: valueList.length == viewPackageNameList.length,
            allValueList: viewPackageNameList,
          )
        : null;
    final hasChanges = ref.watch(
      vpnSettingProvider.select(
        (state) =>
            _getRealAccessControlProps(state.accessControlProps) !=
            _getRealAccessControlProps(accessControl),
      ),
    );
    return CommonPopScope(
      onPop: hasChanges
          ? (_) {
              _handleBack();
              return false;
            }
          : null,
      child: CommonScaffold(
        isLoading: isLoading,
        searchState: AppBarSearchState(onSearch: _onSearch),
        searchActions: [?selectAllAction],
        searchInBar: true,
        title: appLocalizations.appAccessControl,
        confirmationAction: hasChanges
            ? IconButtonData(
                glyph: AppGlyphs.check,
                onPressed: _handleSave,
                tooltip: appLocalizations.save,
              )
            : null,
        iconActions: [
          ?selectAllAction,
          IconButtonData(
            glyph: AppGlyphs.info,
            onPressed: _showLegend,
            tooltip: appLocalizations.tip,
          ),
        ],
        menuItems: _buildMenuItems(context, accessControl, vpnSetting),
        body: needsInstalledAppsPermission
            ? _buildInstalledAppsPermissionStatus()
            : FloatingFootBar(
                bar: _AccessStatus(
                  accessControl: accessControl,
                  selectedCount: valueList.length,
                  onEnable: () =>
                      _update((state) => state.copyWith(enable: true)),
                ),
                body: _buildContent(
                  packages: viewPackages,
                  accessControl: accessControl,
                  processRules: processRules,
                  showProfile: showProfile,
                  isSearching: query.isNotEmpty,
                ),
              ),
      ),
    );
  }
}

class _AccessStatus extends StatelessWidget {
  const _AccessStatus({
    required this.accessControl,
    required this.selectedCount,
    required this.onEnable,
  });

  final AccessControlProps accessControl;
  final int selectedCount;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final enabled = accessControl.enable;
    final description = enabled
        ? switch (accessControl.mode) {
            AccessControlMode.acceptSelected =>
              appLocalizations.accessControlAllowDesc,
            AccessControlMode.rejectSelected =>
              appLocalizations.accessControlNotAllowDesc,
          }
        : appLocalizations.accessControlDisabledDesc;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 6, enabled ? 16 : 8, 6),
      child: Row(
        spacing: 12,
        children: [
          GlyphIcon(
            enabled ? AppGlyphs.appsList : AppGlyphs.info,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurface),
            ),
          ),
          if (enabled)
            TonalChip(
              label: appLocalizations.accessControlSelectedCount(selectedCount),
              color: colorScheme.primary.opacity15,
              foregroundColor: colorScheme.primary,
            )
          else
            TonalButton(
              size: TonalButtonSize.compact,
              label: appLocalizations.turnOn,
              onPressed: onEnable,
            ),
        ],
      ),
    );
  }
}

class PackageListItem extends StatelessWidget {
  final Package package;

  /// The manual mark: checked is the mode's list, empty the opposite one, a
  /// dash means no choice.
  final bool? value;

  /// Where the profile's own rule sends the app, or null when no rule covers
  /// it: the rule decides the check, the target names it.
  final String? profileTarget;

  /// The whitelist picks its apps on its own, so its profile column is gone.
  final bool showProfile;
  final VoidCallback onChanged;

  const PackageListItem({
    super.key,
    required this.package,
    required this.value,
    required this.profileTarget,
    this.showProfile = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return ListItem(
      leading: PackageIcon(packageName: package.packageName, size: 48),
      title: Text(
        package.label,
        style: const TextStyle(overflow: TextOverflow.ellipsis),
        maxLines: 1,
      ),
      subtitle: Text(
        package.packageName,
        style: const TextStyle(overflow: TextOverflow.ellipsis),
        maxLines: 1,
      ),
      onTap: onChanged,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: appLocalizations.vpnExclusionsManual,
            child: CommonCheckBox(
              value: value,
              tristate: true,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (showProfile)
            Tooltip(
              message: profileTarget == null
                  ? appLocalizations.vpnExclusionsProfile
                  : '${appLocalizations.vpnExclusionsProfile}: $profileTarget',
              child: GestureDetector(
                // The column only reports what the profile says: a tap on it
                // must not reach the row and cycle the manual mark.
                onTap: () {},
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CommonCheckBox(
                      value: profileTarget == null ? null : true,
                      tristate: true,
                      compact: true,
                      onChanged: null,
                    ),
                    if (profileTarget != null)
                      Text(
                        profileTarget == RuleTarget.DIRECT.value
                            ? RuleTarget.DIRECT.value
                            : appLocalizations.accessControlTargetProxy,
                        maxLines: 1,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

List<CommonPopupMenuItem> _optionsSection<T>({
  required String title,
  required List<T> options,
  required T value,
  required String Function(T option) textOf,
  required ValueSetter<T> onSelected,
}) {
  return [
    for (final option in options)
      CommonPopupMenuItem(
        label: textOf(option),
        checked: option == value,
        section: option == options.first
            ? CommonPopupMenuSection(title: title)
            : null,
        onPressed: () => onSelected(option),
      ),
  ];
}
