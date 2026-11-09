import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<RealProfile> _buildProfile(
  Map<String, dynamic> rawConfig, {
  List<Rule> addedRules = const [],
}) {
  return makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: addedRules,
      defaultUA: 'FlClash-Test',
    ),
  );
}

void main() {
  test('processNameTargets keeps the first rule that names an app', () {
    final targets = processNameTargets([
      'PROCESS-NAME,com.example.first,DIRECT',
      'PROCESS-NAME,com.example.first,Proxy',
      'PROCESS-NAME,com.example.second,HK',
      'process-name,com.example.lower,direct',
      'DOMAIN-SUFFIX,example.com,DIRECT',
    ]);

    expect(targets, {
      'com.example.first': 'DIRECT',
      'com.example.second': 'HK',
      'com.example.lower': 'DIRECT',
    });
  });

  test('processNameTargets skips rules that name no app or no target', () {
    final targets = processNameTargets([
      'PROCESS-NAME,,DIRECT',
      'PROCESS-NAME,com.example.app',
      r'PROCESS-NAME-REGEX,com\.example\..*,DIRECT',
    ]);

    expect(targets, isEmpty);
  });

  test('processNameTargets reads an inline classical rule-set', () {
    final targets = processNameTargets(
      [
        'RULE-SET,ru-mobile-apps,direct',
        'RULE-SET,ru-mobile-domains,DIRECT',
        'PROCESS-NAME,com.example.late,Proxy',
      ],
      {
        'ru-mobile-apps': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': [
            'PROCESS-NAME,com.example.gosuslugi',
            'PROCESS-NAME,com.example.ozon,DIRECT',
            'DOMAIN-SUFFIX,ozon.ru',
            'RULE-SET,nested,DIRECT',
          ],
        },
        'ru-mobile-domains': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['DOMAIN-SUFFIX,ozon.ru'],
        },
      },
    );

    expect(targets, {
      'com.example.gosuslugi': 'DIRECT',
      'com.example.ozon': 'DIRECT',
      'com.example.late': 'PROXY',
    });
  });

  test('a rule before the rule-set keeps the first match', () {
    final targets = processNameTargets(
      [
        'PROCESS-NAME,com.example.app,Proxy',
        'RULE-SET,apps,DIRECT',
      ],
      {
        'apps': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['PROCESS-NAME,com.example.app'],
        },
      },
    );

    expect(targets, {'com.example.app': 'PROXY'});
  });

  test('rule-sets that hold no rule lines are skipped', () {
    final targets = processNameTargets(
      ['RULE-SET,domains,DIRECT', 'RULE-SET,remote,DIRECT'],
      {
        'domains': {
          'type': 'inline',
          'behavior': 'domain',
          'payload': ['ozon.ru'],
        },
        'remote': {
          'type': 'http',
          'behavior': 'classical',
          'url': 'https://example.com/rules.yaml',
        },
      },
    );

    expect(targets, isEmpty);
  });

  test('makeRealProfileTask publishes the profile rules by package', () async {
    final result = await _buildProfile(
      {
        'rules': [
          'PROCESS-NAME,com.example.direct,DIRECT',
          'PROCESS-NAME,com.example.proxy,Proxy',
          'MATCH,Proxy',
        ],
      },
      addedRules: const [
        Rule(
          ruleAction: RuleAction.PROCESS_NAME,
          content: 'com.example.added',
          ruleTarget: 'DIRECT',
        ),
      ],
    );

    expect(result.processRules, {
      'com.example.added': 'DIRECT',
      'com.example.direct': 'DIRECT',
      'com.example.proxy': 'PROXY',
    });
  });

  test('makeRealProfileTask reads inline rule-providers too', () async {
    final result = await _buildProfile({
      'rules': ['RULE-SET,ru-mobile-apps,DIRECT', 'MATCH,Proxy'],
      'rule-providers': {
        'ru-mobile-apps': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['PROCESS-NAME,ru.ozon.app.android'],
        },
      },
    });

    expect(result.processRules, {'ru.ozon.app.android': 'DIRECT'});
  });
}
