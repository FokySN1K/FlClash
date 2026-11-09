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
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The apps the tunnel leaves alone. A rule inside the Core only picks an exit,
/// while an app that judges the VPN by its interfaces keeps seeing them, so the
/// only way out for it is to stay out of the tunnel itself.
class ExclusionsView extends ConsumerStatefulWidget {
  const ExclusionsView({super.key});

  @override
  ConsumerState<ExclusionsView> createState() => _ExclusionsViewState();
}

class _ExclusionsViewState extends ConsumerState<ExclusionsView>
    with RouteSettledMixin<ExclusionsView> {
  late ScrollController _controller;
  late Set<String> _excluded;
  late Set<String> _included;
  final _completer = Completer();
  bool _installedAppsPermissionGranted = true;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
    final vpnSetting = ref.read(vpnSettingProvider);
    _excluded = vpnSetting.excludePackages.toSet();
    _included = vpnSetting.includePackages.toSet();
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

  /// The manual mark: checked keeps the app out of the tunnel, empty is against
  /// the exclusion, a dash means no choice at all.
  bool? _manualState(String packageName) {
    if (_excluded.contains(packageName)) {
      return true;
    }
    if (_included.contains(packageName)) {
      return false;
    }
    return null;
  }

  /// No choice -> excluded -> kept inside -> no choice.
  void _cycleManual(String packageName) {
    setState(() {
      switch (_manualState(packageName)) {
        case null:
          _excluded.add(packageName);
          _included.remove(packageName);
        case true:
          _excluded.remove(packageName);
          _included.add(packageName);
        case false:
          _included.remove(packageName);
      }
    });
  }

  /// What the profile's own rule says: checked sends the app DIRECT, empty
  /// sends it through a proxy, a dash says nothing. Global mode ignores the
  /// rules altogether, so nothing is shown there.
  bool? _profileState(
    String packageName,
    Map<String, String> processRules,
    Mode mode,
  ) {
    if (mode == Mode.global) {
      return null;
    }
    final target = processRules[packageName];
    if (target == null) {
      return null;
    }
    return target == RuleTarget.DIRECT.value;
  }

  int _rank(String packageName, Map<String, String> processRules, Mode mode) {
    if (_manualState(packageName) != null) {
      return 0;
    }
    if (_profileState(packageName, processRules, mode) != null) {
      return 1;
    }
    return 2;
  }

  bool _sameSet(Set<String> local, List<String> saved) {
    return local.length == saved.length && local.containsAll(saved);
  }

  void _handleSave() {
    ref
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            excludePackages: _excluded.toList()..sort(),
            includePackages: _included.toList()..sort(),
          ),
        );
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

  Future<void> _showLegend() async {
    final appLocalizations = context.appLocalizations;
    // With the profile rules ignored there is no profile column to explain.
    final ignoreProfileRules = ref
        .read(vpnSettingProvider)
        .ignoreProfileProcessRules;
    await dialogs.showMessage(
      message: TextSpan(
        text: [
          appLocalizations.vpnExclusionsManualHint,
          if (!ignoreProfileRules) appLocalizations.vpnExclusionsProfileHint,
          appLocalizations.vpnExclusionsLockdown,
        ].join('\n\n'),
      ),
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

  Widget _buildContent({
    required List<Package> packages,
    required Map<String, String> processRules,
    required Mode mode,
    required bool isSearching,
  }) {
    final appLocalizations = context.appLocalizations;
    return FutureBuilder(
      future: _completer.future,
      builder: (context, snapshot) {
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
                return _ExclusionItem(
                  key: Key(package.packageName),
                  package: package,
                  manual: _manualState(package.packageName),
                  profile: _profileState(
                    package.packageName,
                    processRules,
                    mode,
                  ),
                  onManualChanged: () => _cycleManual(package.packageName),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.exclusions).notifier).value = value;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final query = SearchQuery(ref.watch(queryProvider(QueryTag.exclusions)));
    final packages = ref.watch(packagesProvider);
    final saved = ref.watch(vpnSettingProvider);
    // Ignored profile rules must not rank or tick the apps either.
    final processRules = saved.ignoreProfileProcessRules
        ? const <String, String>{}
        : ref.watch(profileProcessRulesProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final hasChanges =
        !_sameSet(_excluded, saved.excludePackages) ||
        !_sameSet(_included, saved.includePackages);
    final viewPackages =
        packages
            .whereMatches(
              query,
              (package) => [package.label, package.packageName],
            )
            .toList()
          ..sort((a, b) {
            final rankA = _rank(a.packageName, processRules, mode);
            final rankB = _rank(b.packageName, processRules, mode);
            if (rankA != rankB) {
              return rankA.compareTo(rankB);
            }
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });
    final needsInstalledAppsPermission =
        packages.isEmpty && !_installedAppsPermissionGranted;
    return CommonPopScope(
      onPop: hasChanges
          ? (_) {
              _handleBack();
              return false;
            }
          : null,
      child: CommonScaffold(
        searchState: AppBarSearchState(onSearch: _onSearch),
        searchInBar: true,
        title: appLocalizations.vpnExclusions,
        confirmationAction: hasChanges
            ? IconButtonData(
                glyph: AppGlyphs.check,
                onPressed: _handleSave,
                tooltip: appLocalizations.save,
              )
            : null,
        iconActions: [
          IconButtonData(
            glyph: AppGlyphs.info,
            onPressed: _showLegend,
            tooltip: appLocalizations.vpnExclusions,
          ),
        ],
        body: needsInstalledAppsPermission
            ? _buildInstalledAppsPermissionStatus()
            : FloatingFootBar(
                bar: _ExclusionsStatus(
                  mode: mode,
                  ignored: saved.ignoreProfileProcessRules,
                ),
                body: _buildContent(
                  packages: viewPackages,
                  processRules: processRules,
                  mode: mode,
                  isSearching: query.isNotEmpty,
                ),
              ),
      ),
    );
  }
}

class _ExclusionItem extends StatelessWidget {
  const _ExclusionItem({
    super.key,
    required this.package,
    required this.manual,
    required this.profile,
    required this.onManualChanged,
  });

  final Package package;
  final bool? manual;
  final bool? profile;
  final VoidCallback onManualChanged;

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
      onTap: onManualChanged,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: appLocalizations.vpnExclusionsManual,
            child: CommonCheckBox(
              value: manual,
              tristate: true,
              onChanged: (_) => onManualChanged(),
            ),
          ),
          Tooltip(
            message: appLocalizations.vpnExclusionsProfile,
            child: GestureDetector(
              // The box only reports what the yaml says: a tap on it must not
              // reach the row and flip the manual mark.
              onTap: () {},
              child: CommonCheckBox(
                value: profile,
                tristate: true,
                onChanged: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExclusionsStatus extends StatelessWidget {
  const _ExclusionsStatus({required this.mode, required this.ignored});

  final Mode mode;
  final bool ignored;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final description = switch ((ignored, mode)) {
      (true, _) => appLocalizations.ignoreProfileProcessRulesDesc,
      (false, Mode.global) => appLocalizations.vpnExclusionsGlobalMode,
      _ => appLocalizations.vpnExclusionsDesc,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
      child: Row(
        spacing: 12,
        children: [
          GlyphIcon(
            AppGlyphs.info,
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
        ],
      ),
    );
  }
}
