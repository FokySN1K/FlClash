import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    // One build keeps the chain alive: the tunnel options watch the
    // auto-dispose settings a test updates afterwards.
    await container.read(vpnOptionsProvider.future);
  });

  tearDown(() => container.dispose());

  Future<List<String>> excludedPackages() async {
    final options = await container.read(vpnOptionsProvider.future);
    return options.excludePackages;
  }

  test('manual exclusions reach the tunnel options', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(excludePackages: const ['com.example.chat']),
        );

    expect(await excludedPackages(), ['com.example.chat']);
  });

  test('the profile rules exclude the apps they send DIRECT', () async {
    container
        .read(profileProcessRulesProvider.notifier)
        .update(
          ProcessRules.names({
            'com.example.direct': 'DIRECT',
            'com.example.proxy': 'PROXY',
          }),
        );

    expect(await excludedPackages(), ['com.example.direct']);
  });

  test('a wildcard rule needs the app list to name its apps', () async {
    container
        .read(profileProcessRulesProvider.notifier)
        .update(
          const ProcessRules([
            ProcessRuleEntry.wildcard('com.example.*', 'DIRECT'),
          ]),
        );

    expect(await excludedPackages(), isEmpty);
  });

  test('a wildcard rule excludes the installed apps it covers', () async {
    container.read(packagesProvider.notifier).value = const [
      Package(
        packageName: 'com.example.direct',
        label: 'Direct',
        system: false,
        internet: true,
        lastUpdateTime: 0,
      ),
      Package(
        packageName: 'com.example.inside',
        label: 'Inside',
        system: false,
        internet: true,
        lastUpdateTime: 0,
      ),
    ];
    container
        .read(profileProcessRulesProvider.notifier)
        .update(
          const ProcessRules([
            ProcessRuleEntry.wildcard('com.example.d*', 'DIRECT'),
          ]),
        );

    expect(await excludedPackages(), ['com.example.direct']);
  });

  test('the ignored profile rules leave the apps inside the tunnel', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(ignoreProfileProcessRules: true));
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), isEmpty);
  });

  test('ignoring the profile rules keeps manual marks working', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            ignoreProfileProcessRules: true,
            excludePackages: const ['com.example.chat'],
          ),
        );
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), ['com.example.chat']);
  });

  test('global mode keeps the profile DIRECT apps out too', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), ['com.example.direct']);
  });

  test('the whitelist picks its apps on its own', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            accessControlProps: const AccessControlProps(
              enable: true,
              mode: AccessControlMode.acceptSelected,
            ),
            includePackages: const ['com.example.allowed'],
          ),
        );
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), isEmpty);
  });

  test('the whitelist keeps a manual exclusion', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            accessControlProps: const AccessControlProps(
              enable: true,
              mode: AccessControlMode.acceptSelected,
            ),
            excludePackages: const ['com.example.chat'],
          ),
        );
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), ['com.example.chat']);
  });

  test('the switch off leaves every app inside the tunnel', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            accessControlProps: const AccessControlProps(),
            excludePackages: const ['com.example.chat'],
            includePackages: const ['com.example.direct'],
          ),
        );
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), isEmpty);
  });

  test('a manual inclusion cancels a profile exclusion', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(includePackages: const ['com.example.direct']),
        );
    container
        .read(profileProcessRulesProvider.notifier)
        .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

    expect(await excludedPackages(), isEmpty);
  });

  test(
    'a manual exclusion stands beside the profile rule in global mode',
    () async {
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.global));
      container
          .read(vpnSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(excludePackages: const ['com.example.chat']),
          );
      container
          .read(profileProcessRulesProvider.notifier)
          .update(ProcessRules.names({'com.example.direct': 'DIRECT'}));

      expect(await excludedPackages(), [
        'com.example.chat',
        'com.example.direct',
      ]);
    },
  );
}
