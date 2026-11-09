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
import 'package:fl_clash/views/exclusions.dart';
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
}) {
  return Package(
    packageName: name,
    label: label ?? name.split('.').last,
    system: system,
    internet: internet,
    lastUpdateTime: 0,
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
  List<Package> grantedPackages = const [];
  int loadCount = 0;

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
  Future<bool> requestInstalledAppsPermission() async => true;
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
    container.listen(vpnSettingProvider, (_, _) {});
    container.listen(patchClashConfigProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  void seedVpn({
    List<String> exclude = const [],
    List<String> include = const [],
  }) {
    container.read(vpnSettingProvider.notifier).value = const VpnProps()
        .copyWith(excludePackages: exclude, includePackages: include);
  }

  Future<void> pumpExclusionsView(WidgetTester tester) async {
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
        child: const TestApp(child: ExclusionsView()),
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

  testWidgets('the manual box cycles through no choice, excluded, kept '
      'inside', (tester) async {
    seedVpn();
    await pumpExclusionsView(tester);

    expect(boxValue(tester, manualBox('com.example.browser')), isNull);
    expect(boxValue(tester, profileBox('com.example.browser')), isNull);

    await tester.tap(manualBox('com.example.browser'));
    await tester.pump();
    expect(boxValue(tester, manualBox('com.example.browser')), isTrue);
    expect(find.byTooltip('Save'), findsOneWidget);

    await tester.tap(manualBox('com.example.browser'));
    await tester.pump();
    expect(boxValue(tester, manualBox('com.example.browser')), isFalse);

    await tester.tap(manualBox('com.example.browser'));
    await tester.pump();
    expect(boxValue(tester, manualBox('com.example.browser')), isNull);
    expect(find.byTooltip('Save'), findsNothing);

    await teardownView(tester);
  });

  testWidgets('the profile box shows what the yaml sends and takes no taps', (
    tester,
  ) async {
    seedVpn();
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.browser': 'DIRECT',
      'com.example.chat': 'PROXY',
    });
    await pumpExclusionsView(tester);

    expect(boxValue(tester, profileBox('com.example.browser')), isTrue);
    expect(boxValue(tester, profileBox('com.example.chat')), isFalse);
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

  testWidgets('global mode blanks the profile column and keeps manual marks', (
    tester,
  ) async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    seedVpn(exclude: ['com.example.chat']);
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.browser': 'DIRECT',
    });
    await pumpExclusionsView(tester);
    final l10n = AppLocalizations.current;

    expect(boxValue(tester, profileBox('com.example.browser')), isNull);
    expect(boxValue(tester, manualBox('com.example.chat')), isTrue);
    expect(find.text(l10n.vpnExclusionsGlobalMode), findsOneWidget);

    await teardownView(tester);
  });

  testWidgets('ignored profile rules blank the profile column and say so', (
    tester,
  ) async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            ignoreProfileProcessRules: true,
            excludePackages: const ['com.example.chat'],
          ),
        );
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.browser': 'DIRECT',
    });
    await pumpExclusionsView(tester);
    final l10n = AppLocalizations.current;

    expect(boxValue(tester, profileBox('com.example.browser')), isNull);
    expect(boxValue(tester, manualBox('com.example.chat')), isTrue);
    expect(find.text(l10n.ignoreProfileProcessRulesDesc), findsOneWidget);

    await teardownView(tester);
  });

  testWidgets('save stores both manual lists', (tester) async {
    seedVpn();
    await pumpExclusionsView(tester);

    await tester.tap(manualBox('com.example.browser'));
    await tester.pump();
    await tester.tap(manualBox('com.example.chat'));
    await tester.pump();
    await tester.tap(manualBox('com.example.chat'));
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pump();

    final saved = container.read(vpnSettingProvider);
    expect(saved.excludePackages, ['com.example.browser']);
    expect(saved.includePackages, ['com.example.chat']);
    expect(find.byTooltip('Save'), findsNothing);

    await teardownView(tester);
  });

  testWidgets('the search field filters the installed apps', (tester) async {
    seedVpn();
    await pumpExclusionsView(tester);

    await tester.tap(find.byGlyph(AppGlyphs.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nothing matches');
    await tester.pumpAndSettle();

    expect(find.text('Browser'), findsNothing);
    expect(find.text(AppLocalizations.current.noSearchResults), findsOneWidget);

    await teardownView(tester);
  });
}
