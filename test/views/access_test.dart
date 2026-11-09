import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

Package _package(
  String name, {
  String? label,
  bool system = false,
  bool internet = true,
  int lastUpdateTime = 0,
}) {
  return Package(
    packageName: name,
    label: label ?? name.split('.').last,
    system: system,
    internet: internet,
    lastUpdateTime: lastUpdateTime,
  );
}

final _packages = [
  _package('com.example.browser', label: 'Browser'),
  _package('com.example.chat', label: 'Chat'),
  _package('com.android.settings', label: 'Settings', system: true),
  _package('com.example.offline', label: 'Offline', internet: false),
];

class _TestSystemAction extends SystemAction {
  bool installedAppsPermissionGranted = true;
  bool grantOnRequest = true;
  int requestCount = 0;
  int loadCount = 0;
  List<Package> grantedPackages = const [];

  @override
  Future<List<Package>> getPackages() async {
    loadCount++;
    if (installedAppsPermissionGranted && grantedPackages.isNotEmpty) {
      ref.read(packagesProvider.notifier).value = grantedPackages;
    }
    return ref.read(packagesProvider);
  }

  @override
  Future<bool> isInstalledAppsPermissionGranted() async =>
      installedAppsPermissionGranted;

  @override
  Future<bool> requestInstalledAppsPermission() async {
    requestCount++;
    installedAppsPermissionGranted = grantOnRequest;
    return grantOnRequest;
  }
}

Future<void> openBarMenu(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byGlyph(AppGlyphs.more),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _TestSystemAction systemAction;

  setUp(() {
    systemAction = _TestSystemAction();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        systemActionProvider.overrideWith(() => systemAction),
      ],
    );
    globalState.container = container;
    container.read(packagesProvider.notifier).value = _packages;
  });

  tearDown(() => container.dispose());

  void seedAccessControl(AccessControlProps props) {
    container.read(vpnSettingProvider.notifier).value = const VpnProps()
        .copyWith(accessControlProps: props);
  }

  Future<void> pumpAccessView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1400, 1400));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: AccessView()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
  }

  Future<void> teardownView(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Finder manualBox(String packageName) => find
      .descendant(
        of: find.byKey(Key(packageName)),
        matching: find.byType(Checkbox),
      )
      .first;

  Finder profileBox(String packageName) => find
      .descendant(
        of: find.byKey(Key(packageName)),
        matching: find.byType(Checkbox),
      )
      .last;

  bool? boxValue(WidgetTester tester, Finder finder) =>
      tester.widget<Checkbox>(finder).value;

  group('visible package list', () {
    testWidgets('hides system and offline apps by default', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));

      await pumpAccessView(tester);

      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Offline'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('shows system apps once the filter is disabled', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(enable: true, isFilterSystemApp: false),
      );

      await pumpAccessView(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('shows offline apps once the internet filter is disabled', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(enable: true, isFilterNonInternetApp: false),
      );

      await pumpAccessView(tester);

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('the settings sub menu shows system apps from a check', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder inMenu(Finder finder) =>
          find.descendant(of: find.byType(CommonPopupMenu), matching: finder);

      await openBarMenu(tester);
      await tester.tap(inMenu(find.text(l10n.settings)).last);
      await tester.pumpAndSettle();
      expect(inMenu(find.text(l10n.source)), findsOneWidget);
      await tester.tap(inMenu(find.text(l10n.systemApp)));
      await tester.pumpAndSettle();

      final state = container.read(accessControlStateProvider);
      expect(state.isFilterSystemApp, isFalse);
      expect(state.isFilterNonInternetApp, isTrue);
      expect(find.byType(CommonPopupMenu), findsNothing);
      expect(find.text('Settings'), findsOneWidget);

      await teardownView(tester);
    });

    testWidgets('the settings sub menu switches the mode', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder inMenu(Finder finder) =>
          find.descendant(of: find.byType(CommonPopupMenu), matching: finder);

      await openBarMenu(tester);
      await tester.tap(inMenu(find.text(l10n.settings)).last);
      await tester.pumpAndSettle();
      await tester.tap(inMenu(find.text(l10n.whitelistMode)));
      await tester.pumpAndSettle();

      expect(
        container.read(accessControlStateProvider).mode,
        AccessControlMode.acceptSelected,
      );
      await openBarMenu(tester);
      expect(inMenu(find.text(l10n.whitelistMode)), findsOneWidget);

      await teardownView(tester);
    });

    testWidgets('sorts by name when the name sort is selected', (tester) async {
      seedAccessControl(
        const AccessControlProps(enable: true, sort: AccessSortType.name),
      );

      await pumpAccessView(tester);

      final labels = tester
          .widgetList<PackageListItem>(find.byType(PackageListItem))
          .map((item) => item.package.label)
          .toList();
      expect(labels, ['Browser', 'Chat']);

      await teardownView(tester);
    });
  });

  group('search', () {
    testWidgets('filters by label and by package name', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      container.read(queryProvider(QueryTag.access).notifier).value = 'chat';
      await tester.pump();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Browser'), findsNothing);

      container.read(queryProvider(QueryTag.access).notifier).value =
          'com.example.browser';
      await tester.pump();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('ignores case and needs every term to match', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      container.read(queryProvider(QueryTag.access).notifier).value = 'CHAT';
      await tester.pump();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Browser'), findsNothing);

      container.read(queryProvider(QueryTag.access).notifier).value =
          'EXAMPLE browser';
      await tester.pump();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('the app bar search field filters the list', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      await tester.tap(find.byGlyph(AppGlyphs.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nothing matches');
      await tester.pumpAndSettle();

      expect(find.text('Browser'), findsNothing);
      expect(
        find.text(AppLocalizations.current.noSearchResults),
        findsOneWidget,
      );

      await teardownView(tester);
    });
  });

  group('selection', () {
    testWidgets('the manual box cycles through no choice, the mode list and '
        'the other list', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      expect(boxValue(tester, manualBox('com.example.browser')), isNull);

      await tester.tap(find.text('Browser'));
      await tester.pump();
      var state = container.read(accessControlStateProvider);
      expect(state.rejectList, ['com.example.browser']);
      expect(state.acceptList, isEmpty);
      expect(boxValue(tester, manualBox('com.example.browser')), isTrue);

      await tester.tap(find.text('Browser'));
      await tester.pump();
      state = container.read(accessControlStateProvider);
      expect(state.rejectList, isEmpty);
      expect(state.acceptList, ['com.example.browser']);
      expect(boxValue(tester, manualBox('com.example.browser')), isFalse);

      await tester.tap(find.text('Browser'));
      await tester.pump();
      state = container.read(accessControlStateProvider);
      expect(state.rejectList, isEmpty);
      expect(state.acceptList, isEmpty);
      expect(boxValue(tester, manualBox('com.example.browser')), isNull);

      await teardownView(tester);
    });

    testWidgets('the bar at the foot says access control is off and turns '
        'it on', (tester) async {
      seedAccessControl(const AccessControlProps());
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;

      expect(find.text(l10n.accessControlDisabledDesc), findsOneWidget);
      await tester.tap(find.widgetWithText(TonalButton, l10n.turnOn));
      await tester.pump();

      expect(container.read(accessControlStateProvider).enable, isTrue);
      expect(find.text(l10n.accessControlDisabledDesc), findsNothing);
      expect(find.text(l10n.accessControlNotAllowDesc), findsOneWidget);

      await teardownView(tester);
    });

    testWidgets('the bar at the foot follows the mode and counts the '
        'selected apps', (tester) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          rejectList: ['com.example.browser'],
        ),
      );
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;

      expect(find.text(l10n.accessControlNotAllowDesc), findsOneWidget);
      expect(find.text(l10n.accessControlSelectedCount(1)), findsOneWidget);

      await tester.tap(find.text('Chat'));
      await tester.pump();
      expect(find.text(l10n.accessControlSelectedCount(2)), findsOneWidget);

      container
          .read(accessControlStateProvider.notifier)
          .update(
            (state) => state.copyWith(mode: AccessControlMode.acceptSelected),
          );
      await tester.pump();
      expect(find.text(l10n.accessControlAllowDesc), findsOneWidget);
      expect(find.text(l10n.accessControlSelectedCount(0)), findsOneWidget);

      await teardownView(tester);
    });

    testWidgets('select all stands beside search, then folds for save', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      expect(
        find.ancestor(
          of: find.byTooltip('Select all'),
          matching: find.ancestor(
            of: find.byTooltip('Search'),
            matching: find.byType(TonalButtonGroup),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(
        [...container.read(accessControlStateProvider).currentList]..sort(),
        ['com.example.browser', 'com.example.chat'],
      );

      expect(find.byTooltip('Save'), findsOneWidget);
      expect(find.byTooltip('Deselect all'), findsNothing);
      await openBarMenu(tester);
      await tester.tap(find.text('Deselect all'));
      await tester.pumpAndSettle();
      expect(container.read(accessControlStateProvider).currentList, isEmpty);

      await teardownView(tester);
    });

    testWidgets('the bar menu turns access control on and off in a section', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder inMenu(Finder finder) =>
          find.descendant(of: find.byType(CommonPopupMenu), matching: finder);
      Finder checkOn(String label) => inMenu(
        find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
          matching: find.byGlyph(AppGlyphs.check),
        ),
      );

      await openBarMenu(tester);
      expect(inMenu(find.text(l10n.accessControl)), findsOneWidget);
      expect(inMenu(find.text(l10n.blacklistMode)), findsOneWidget);
      expect(checkOn(l10n.turnOn), findsOneWidget);
      expect(checkOn(l10n.turnOff), findsNothing);

      await tester.tap(inMenu(find.text(l10n.turnOff)));
      await tester.pumpAndSettle();
      expect(container.read(accessControlStateProvider).enable, isFalse);

      await openBarMenu(tester);
      expect(checkOn(l10n.turnOn), findsNothing);
      expect(checkOn(l10n.turnOff), findsOneWidget);

      await tester.tap(inMenu(find.text(l10n.turnOn)));
      await tester.pumpAndSettle();
      expect(container.read(accessControlStateProvider).enable, isTrue);

      await teardownView(tester);
    });

    testWidgets('searching selects then clears only the matching apps', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chat');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(container.read(accessControlStateProvider).currentList, [
        'com.example.chat',
      ]);

      await tester.tap(find.byTooltip('Deselect all'));
      await tester.pumpAndSettle();
      expect(container.read(accessControlStateProvider).currentList, isEmpty);

      await teardownView(tester);
    });

    testWidgets('selection targets the accept list in accept mode', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          mode: AccessControlMode.acceptSelected,
        ),
      );
      await pumpAccessView(tester);

      await tester.tap(find.text('Chat'));
      await tester.pump();

      final state = container.read(accessControlStateProvider);
      expect(state.acceptList, ['com.example.chat']);
      expect(state.rejectList, isEmpty);

      await teardownView(tester);
    });
  });

  group('profile rules', () {
    testWidgets('the profile box shows what the rules say and takes no taps', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      container
          .read(profileProcessRulesProvider.notifier)
          .update(
            ProcessRules.names({
              'com.example.browser': 'DIRECT',
              'com.example.chat': 'PROXY',
            }),
          );
      await pumpAccessView(tester);

      expect(boxValue(tester, profileBox('com.example.browser')), isTrue);
      expect(boxValue(tester, profileBox('com.example.chat')), isTrue);
      expect(boxValue(tester, manualBox('com.example.browser')), isNull);

      final onChanged = tester
          .widget<Checkbox>(profileBox('com.example.browser'))
          .onChanged;
      expect(onChanged, isNull);

      await tester.tap(profileBox('com.example.browser'));
      await tester.pump();
      expect(boxValue(tester, profileBox('com.example.browser')), isTrue);
      expect(boxValue(tester, manualBox('com.example.browser')), isNull);

      await teardownView(tester);
    });

    testWidgets('the profile column names the rule target', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      container
          .read(profileProcessRulesProvider.notifier)
          .update(
            ProcessRules.names({
              'com.example.browser': 'DIRECT',
              'com.example.chat': '📺 YouTube с резервом',
            }),
          );
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;

      expect(
        find.descendant(
          of: find.byKey(const Key('com.example.browser')),
          matching: find.text(RuleTarget.DIRECT.value),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('com.example.chat')),
          matching: find.text(l10n.accessControlTargetProxy),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('com.example.browser')),
          matching: find.text(l10n.accessControlTargetProxy),
        ),
        findsNothing,
      );

      await teardownView(tester);
    });

    testWidgets('a mark does not move the row', (tester) async {
      seedAccessControl(
        const AccessControlProps(enable: true, sort: AccessSortType.name),
      );
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.browser': 'DIRECT'}));
      await pumpAccessView(tester);

      List<String> labels() => tester
          .widgetList<PackageListItem>(find.byType(PackageListItem))
          .map((item) => item.package.label)
          .toList();
      expect(labels(), ['Browser', 'Chat']);

      await tester.tap(manualBox('com.example.chat'));
      await tester.pump();

      expect(container.read(accessControlStateProvider).rejectList, [
        'com.example.chat',
      ]);
      expect(labels(), ['Browser', 'Chat']);

      await teardownView(tester);
    });

    testWidgets('the apps the profile names rank before the rest', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(enable: true, sort: AccessSortType.name),
      );
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.chat': 'PROXY'}));
      await pumpAccessView(tester);

      final labels = tester
          .widgetList<PackageListItem>(find.byType(PackageListItem))
          .map((item) => item.package.label)
          .toList();
      expect(labels, ['Chat', 'Browser']);

      await teardownView(tester);
    });

    testWidgets('a wildcard rule ticks every app it covers', (tester) async {
      seedAccessControl(const AccessControlProps(enable: true));
      container
          .read(profileProcessRulesProvider.notifier)
          .update(
            const ProcessRules([
              ProcessRuleEntry.wildcard('com.example.*', 'DIRECT'),
            ]),
          );
      await pumpAccessView(tester);

      expect(boxValue(tester, profileBox('com.example.browser')), isTrue);
      expect(boxValue(tester, profileBox('com.example.chat')), isTrue);

      await teardownView(tester);
    });

    testWidgets('the whitelist hides the profile column', (tester) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          mode: AccessControlMode.acceptSelected,
          sort: AccessSortType.name,
        ),
      );
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.chat': 'DIRECT'}));
      await pumpAccessView(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('com.example.chat')),
          matching: find.byType(Checkbox),
        ),
        findsOneWidget,
      );
      final labels = tester
          .widgetList<PackageListItem>(find.byType(PackageListItem))
          .map((item) => item.package.label)
          .toList();
      expect(labels, ['Browser', 'Chat']);

      await teardownView(tester);
    });

    testWidgets('the settings sub menu hides the profile switch in '
        'the whitelist', (tester) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          mode: AccessControlMode.acceptSelected,
        ),
      );
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder inMenu(Finder finder) =>
          find.descendant(of: find.byType(CommonPopupMenu), matching: finder);

      await openBarMenu(tester);
      await tester.tap(inMenu(find.text(l10n.settings)).last);
      await tester.pumpAndSettle();

      expect(inMenu(find.text(l10n.ignoreProfileProcessRules)), findsNothing);
      expect(inMenu(find.text(l10n.profile)), findsNothing);

      await teardownView(tester);
    });

    testWidgets('global mode keeps the profile column and its marks', (
      tester,
    ) async {
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.global));
      seedAccessControl(
        const AccessControlProps(enable: true, sort: AccessSortType.name),
      );
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.chat': 'DIRECT'}));
      await pumpAccessView(tester);

      expect(boxValue(tester, profileBox('com.example.chat')), isTrue);
      expect(boxValue(tester, manualBox('com.example.chat')), isNull);
      final labels = tester
          .widgetList<PackageListItem>(find.byType(PackageListItem))
          .map((item) => item.package.label)
          .toList();
      expect(labels, ['Chat', 'Browser']);

      await teardownView(tester);
    });

    testWidgets('the legend names the whitelist instead of the profile', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          mode: AccessControlMode.acceptSelected,
        ),
      );
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder legend(String text) => find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.textSpan?.toPlainText() ?? '').contains(text),
      );

      await openBarMenu(tester);
      await tester.tap(find.text(l10n.tip));
      await tester.pumpAndSettle();

      expect(legend(l10n.vpnExclusionsWhitelistMode), findsOneWidget);
      expect(legend(l10n.vpnExclusionsProfileHint), findsNothing);

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      await teardownView(tester);
    });

    testWidgets('the settings sub menu ignores the profile rules', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.browser': 'DIRECT'}));
      await pumpAccessView(tester);
      final l10n = AppLocalizations.current;
      Finder inMenu(Finder finder) =>
          find.descendant(of: find.byType(CommonPopupMenu), matching: finder);

      expect(boxValue(tester, profileBox('com.example.browser')), isTrue);

      await openBarMenu(tester);
      await tester.tap(inMenu(find.text(l10n.settings)).last);
      await tester.pumpAndSettle();
      expect(inMenu(find.text(l10n.profile)), findsOneWidget);
      await tester.tap(inMenu(find.text(l10n.ignoreProfileProcessRules)));
      await tester.pumpAndSettle();

      expect(
        container.read(vpnSettingProvider).ignoreProfileProcessRules,
        isTrue,
      );
      expect(boxValue(tester, profileBox('com.example.browser')), isNull);

      await teardownView(tester);
    });
  });

  testWidgets('asks the platform for the app list on every entry', (
    tester,
  ) async {
    systemAction.grantedPackages = [
      ..._packages,
      _package('com.example.fresh', label: 'Fresh'),
    ];
    seedAccessControl(const AccessControlProps(enable: true));

    await pumpAccessView(tester);

    expect(systemAction.loadCount, 1);
    expect(find.text('Fresh'), findsOneWidget);

    await teardownView(tester);
  });

  group('installed apps permission', () {
    testWidgets('prompts for the permission when the app list is empty', (
      tester,
    ) async {
      container.read(packagesProvider.notifier).value = [];
      systemAction.installedAppsPermissionGranted = false;
      seedAccessControl(const AccessControlProps(enable: true));

      await pumpAccessView(tester);

      expect(find.text('App list permission required'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Authorize'), findsOneWidget);
      expect(find.text('No data'), findsNothing);
      await openBarMenu(tester);
      expect(find.text('Select all'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('keeps the plain empty status once the permission is held', (
      tester,
    ) async {
      container.read(packagesProvider.notifier).value = [];
      seedAccessControl(const AccessControlProps(enable: true));

      await pumpAccessView(tester);

      expect(find.text('No data'), findsOneWidget);
      expect(find.text('App list permission required'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('reloads the app list once the permission is granted', (
      tester,
    ) async {
      container.read(packagesProvider.notifier).value = [];
      systemAction.installedAppsPermissionGranted = false;
      systemAction.grantedPackages = _packages;
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Authorize'));
      await tester.pumpAndSettle();

      expect(systemAction.requestCount, 1);
      expect(find.text('App list permission required'), findsNothing);
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);

      await teardownView(tester);
    });

    testWidgets('offers system settings when the permission stays denied', (
      tester,
    ) async {
      container.read(packagesProvider.notifier).value = [];
      systemAction.installedAppsPermissionGranted = false;
      systemAction.grantOnRequest = false;
      seedAccessControl(const AccessControlProps(enable: true));
      await pumpAccessView(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Authorize'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Settings'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      await teardownView(tester);
    });
  });

  group('save', () {
    testWidgets('offers no save action while nothing has changed', (
      tester,
    ) async {
      seedAccessControl(const AccessControlProps(enable: true));

      await pumpAccessView(tester);
      await openBarMenu(tester);

      expect(find.text('Save'), findsNothing);

      await teardownView(tester);
    });

    testWidgets('drops hidden packages and sorts what it persists', (
      tester,
    ) async {
      seedAccessControl(
        const AccessControlProps(
          enable: true,
          rejectList: ['com.android.settings'],
        ),
      );
      await pumpAccessView(tester);

      await tester.tap(find.text('Chat'));
      await tester.pump();
      await tester.tap(find.text('Browser'));
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final saved = container.read(vpnSettingProvider);
      expect(saved.accessControlProps.rejectList, [
        'com.example.browser',
        'com.example.chat',
      ]);
      expect(saved.excludePackages, [
        'com.example.browser',
        'com.example.chat',
      ]);
      expect(saved.includePackages, isEmpty);

      await teardownView(tester);
    });

    testWidgets('folds the old exclusion marks into the lists on open', (
      tester,
    ) async {
      container.read(vpnSettingProvider.notifier).value = const VpnProps()
          .copyWith(
            accessControlProps: const AccessControlProps(enable: true),
            excludePackages: ['com.example.browser'],
            includePackages: ['com.example.chat'],
          );
      await pumpAccessView(tester);

      expect(boxValue(tester, manualBox('com.example.browser')), isTrue);
      expect(boxValue(tester, manualBox('com.example.chat')), isFalse);

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      final saved = container.read(vpnSettingProvider);
      expect(saved.accessControlProps.rejectList, ['com.example.browser']);
      expect(saved.accessControlProps.acceptList, ['com.example.chat']);
      expect(saved.excludePackages, ['com.example.browser']);
      expect(saved.includePackages, ['com.example.chat']);
      expect(find.byTooltip('Save'), findsNothing);

      await teardownView(tester);
    });
  });
}
