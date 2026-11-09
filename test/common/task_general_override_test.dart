import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _profile = <String, dynamic>{
  'unified-delay': false,
  'tcp-concurrent': false,
  'ipv6': true,
  'geodata-loader': 'standard',
  'find-process-mode': 'strict',
};

Future<YamlMap> _configOf(PatchClashConfig patchConfig) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: _profile,
      realPatchConfig: patchConfig,
      overrides: const ProfileOverrides(),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(result.yaml) as YamlMap;
}

void main() {
  test('leaves the profile alone without picked keys', () async {
    final config = await _configOf(const PatchClashConfig());

    for (final MapEntry(:key, :value) in _profile.entries) {
      expect(config[key], value, reason: key);
    }
  });

  test('replaces only the picked keys', () async {
    final config = await _configOf(
      const PatchClashConfig(
        tcpConcurrent: true,
        geodataLoader: GeodataLoader.memconservative,
        generalOverrideKeys: {
          GeneralOverrideKey.tcpConcurrent,
          GeneralOverrideKey.geodataLoader,
        },
      ),
    );

    expect(config['tcp-concurrent'], true);
    expect(config['geodata-loader'], 'memconservative');
    expect(config['unified-delay'], false);
    expect(config['ipv6'], true);
  });

  test('lets the profile decide the process mode by default', () async {
    final config = await _configOf(
      const PatchClashConfig(findProcessMode: FindProcessMode.always),
    );

    expect(config['find-process-mode'], 'strict',
        reason: 'the profile wins until the override key is picked');
  });

  test('picked process mode replaces the profile value', () async {
    final config = await _configOf(
      const PatchClashConfig(
        findProcessMode: FindProcessMode.always,
        generalOverrideKeys: {GeneralOverrideKey.findProcessMode},
      ),
    );

    expect(config['find-process-mode'], 'always');
  });

  test('keeps the test URL out of the profile', () async {
    final config = await _configOf(
      const PatchClashConfig(
        testUrl: 'https://probe.test/204',
        generalOverrideKeys: {GeneralOverrideKey.testUrl},
      ),
    );

    expect(config.containsKey('test-url'), isFalse);
  });
}
