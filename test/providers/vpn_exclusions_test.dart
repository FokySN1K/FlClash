import 'package:fl_clash/enum/enum.dart';
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
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
      'com.example.proxy': 'PROXY',
    });

    expect(await excludedPackages(), ['com.example.direct']);
  });

  test('the ignored profile rules leave the apps inside the tunnel', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(ignoreProfileProcessRules: true));
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
    });

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
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
    });

    expect(await excludedPackages(), ['com.example.chat']);
  });

  test('global mode stops counting the profile rules', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
    });

    expect(await excludedPackages(), isEmpty);
  });

  test('a manual inclusion cancels a profile exclusion', () async {
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(includePackages: const ['com.example.direct']),
        );
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
    });

    expect(await excludedPackages(), isEmpty);
  });

  test('a manual exclusion wins in every mode', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    container
        .read(vpnSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(excludePackages: const ['com.example.chat']),
        );
    container.read(profileProcessRulesProvider.notifier).update({
      'com.example.direct': 'DIRECT',
    });

    expect(await excludedPackages(), ['com.example.chat']);
  });
}
