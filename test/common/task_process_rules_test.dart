import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

Future<RealProfile> _buildProfile(
  Map<String, dynamic> rawConfig, {
  List<Rule> addedRules = const [],
  String profilesPath = '/profiles',
}) {
  return makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: profilesPath,
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

/// The file the Core downloads a remote set into, as the setup confines it.
String _providerPath(String profilesPath, String name, String url) {
  return providerFilePath(
    profilesPath: profilesPath,
    profileId: 1,
    type: rulesProviderDirectoryName,
    key: '$name@$url',
  );
}

void main() {
  test('exact rules keep the first match and ignore case', () {
    final rules = resolveProcessRules([
      'PROCESS-NAME,com.example.first,DIRECT',
      'PROCESS-NAME,com.example.first,Proxy',
      'PROCESS-NAME,com.example.second,HK',
      'process-name,com.example.lower,direct',
      'DOMAIN-SUFFIX,example.com,DIRECT',
    ]);

    expect(rules.targetFor('com.example.first'), 'DIRECT');
    expect(rules.targetFor('com.example.second'), 'HK');
    expect(rules.targetFor('com.example.lower'), 'DIRECT');
    expect(rules.targetFor('com.example.LOWER'), 'DIRECT');
    expect(rules.targetFor('com.example.other'), isNull);
  });

  test('rules that name no app or no target are skipped', () {
    final rules = resolveProcessRules([
      'PROCESS-NAME,,DIRECT',
      'PROCESS-NAME,com.example.app',
    ]);

    expect(rules.isEmpty, isTrue);
  });

  test('a regex rule matches the apps its pattern names', () {
    final rules = resolveProcessRules([
      r'PROCESS-NAME-REGEX,^com\.example\.(a|b)$,DIRECT',
      r'PROCESS-NAME-REGEX,com\.example\.(,Proxy',
    ]);

    expect(rules.targetFor('com.example.a'), 'DIRECT');
    expect(rules.targetFor('COM.EXAMPLE.B'), 'DIRECT');
    expect(rules.targetFor('com.example.c'), isNull);
    expect(rules.targetFor('com.example.x'), isNull);
  });

  test('a wildcard rule matches the apps its pattern covers', () {
    final rules = resolveProcessRules([
      'PROCESS-NAME-WILDCARD,*.example.*,DIRECT',
      'PROCESS-NAME-WILDCARD,com.?.beta,Proxy',
    ]);

    expect(rules.targetFor('com.example.chat'), 'DIRECT');
    expect(rules.targetFor('COM.EXAMPLE.CHAT'), 'DIRECT');
    expect(rules.targetFor('com.x.beta'), 'PROXY');
    expect(rules.targetFor('com.xy.beta'), isNull);
  });

  test('rules apply in order across kinds', () {
    final rules = resolveProcessRules([
      'PROCESS-NAME,com.example.exact,Proxy',
      'PROCESS-NAME-WILDCARD,com.example.*,DIRECT',
    ]);

    expect(rules.targetFor('com.example.exact'), 'PROXY');
    expect(rules.targetFor('com.example.other'), 'DIRECT');
    expect(rules.hasPatterns, isTrue);
  });

  test('a classical rule-set hands its process lines the set target', () {
    final rules = resolveProcessRules(
      [
        'RULE-SET,ru-mobile-apps,direct',
        'RULE-SET,ru-mobile-domains,DIRECT',
        'PROCESS-NAME,com.example.late,Proxy',
      ],
      ruleProviders: {
        'ru-mobile-apps': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': [
            'PROCESS-NAME,com.example.gosuslugi',
            'PROCESS-NAME,com.example.ozon,DIRECT',
            r'PROCESS-NAME-REGEX,^ru\.',
            'PROCESS-NAME-WILDCARD,ru.*',
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

    expect(rules.targetFor('com.example.gosuslugi'), 'DIRECT');
    expect(rules.targetFor('com.example.ozon'), 'DIRECT');
    expect(rules.targetFor('ru.ozon.app'), 'DIRECT');
    expect(rules.targetFor('com.example.late'), 'PROXY');
  });

  test('a rule before the rule-set keeps the first match', () {
    final rules = resolveProcessRules(
      ['PROCESS-NAME,com.example.app,Proxy', 'RULE-SET,apps,DIRECT'],
      ruleProviders: {
        'apps': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['PROCESS-NAME,com.example.app'],
        },
      },
    );

    expect(rules.targetFor('com.example.app'), 'PROXY');
  });

  test('sets that carry no rule lines are skipped', () {
    final rules = resolveProcessRules(
      ['RULE-SET,domains,DIRECT', 'RULE-SET,remote,DIRECT'],
      ruleProviders: {
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

    expect(rules.isEmpty, isTrue);
  });

  test('a downloaded classical set is read from its confined file', () {
    final root = Directory.systemTemp.createTempSync('flclash-rules');
    addTearDown(() => root.deleteSync(recursive: true));
    const url = 'https://example.com/rules.yaml';
    final path = _providerPath(root.path, 'apps', url);
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'payload:\n'
        '  - PROCESS-NAME,com.example.tg\n'
        r'  - PROCESS-NAME-REGEX,^com\.example\.mail'
        '\n',
      );

    final rules = resolveProcessRules(
      ['RULE-SET,apps,DIRECT'],
      ruleProviders: {
        'apps': {
          'type': 'http',
          'behavior': 'classical',
          'url': url,
          'path': path,
        },
      },
      profilesPath: root.path,
      profileId: 1,
    );

    expect(rules.targetFor('com.example.tg'), 'DIRECT');
    expect(rules.targetFor('com.example.mail'), 'DIRECT');
  });

  test('a text set is read line by line from the file the provider names', () {
    final root = Directory.systemTemp.createTempSync('flclash-rules');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = join(root.path, 'apps.txt');
    File(path).writeAsStringSync(
      '# apps\n'
      '// premium comment\n'
      'PROCESS-NAME,com.example.tg\n'
      '\n'
      'PROCESS-NAME-WILDCARD,ru.*\n',
    );

    final rules = resolveProcessRules(
      ['RULE-SET,apps,DIRECT'],
      ruleProviders: {
        'apps': {
          'type': 'file',
          'behavior': 'classical',
          'format': 'text',
          'path': path,
        },
      },
    );

    expect(rules.targetFor('com.example.tg'), 'DIRECT');
    expect(rules.targetFor('ru.ozon'), 'DIRECT');
  });

  test('a set without a file falls back to its payload', () {
    final rules = resolveProcessRules(
      ['RULE-SET,apps,DIRECT'],
      ruleProviders: {
        'apps': {
          'type': 'http',
          'behavior': 'classical',
          'url': 'https://example.com/rules.yaml',
          'payload': ['PROCESS-NAME,com.example.tg'],
        },
      },
      profilesPath: '/nowhere',
      profileId: 1,
    );

    expect(rules.targetFor('com.example.tg'), 'DIRECT');
  });

  test('an mrs set holds no rule lines', () {
    final root = Directory.systemTemp.createTempSync('flclash-rules');
    addTearDown(() => root.deleteSync(recursive: true));
    const url = 'https://example.com/rules.mrs';
    final path = _providerPath(root.path, 'apps', url);
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('PROCESS-NAME,com.example.tg\n');

    final rules = resolveProcessRules(
      ['RULE-SET,apps,DIRECT'],
      ruleProviders: {
        'apps': {
          'type': 'http',
          'behavior': 'classical',
          'format': 'mrs',
          'url': url,
          'path': path,
        },
      },
      profilesPath: root.path,
      profileId: 1,
    );

    expect(rules.isEmpty, isTrue);
  });

  test('makeRealProfileTask publishes the profile rules in order', () async {
    final result = await _buildProfile(
      {
        'rules': [
          'PROCESS-NAME,com.example.direct,DIRECT',
          'PROCESS-NAME,com.example.proxy,Proxy',
          'PROCESS-NAME-WILDCARD,com.example.*,DIRECT',
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

    expect(result.processRules.targetFor('com.example.added'), 'DIRECT');
    expect(result.processRules.targetFor('com.example.direct'), 'DIRECT');
    expect(result.processRules.targetFor('com.example.proxy'), 'PROXY');
    expect(result.processRules.targetFor('com.example.other'), 'DIRECT');
    expect(result.processRules.hasPatterns, isTrue);
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

    expect(result.processRules.targetFor('ru.ozon.app.android'), 'DIRECT');
  });

  test('makeRealProfileTask reads a downloaded classical set', () async {
    final root = Directory.systemTemp.createTempSync('flclash-rules');
    addTearDown(() => root.deleteSync(recursive: true));
    const url = 'https://example.com/ru-apps.yaml';
    final path = _providerPath(root.path, 'ru-mobile-apps', url);
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('payload:\n  - PROCESS-NAME,ru.ozon.app.android\n');

    final result = await _buildProfile({
      'rules': ['RULE-SET,ru-mobile-apps,DIRECT', 'MATCH,Proxy'],
      'rule-providers': {
        'ru-mobile-apps': {'type': 'http', 'behavior': 'classical', 'url': url},
      },
    }, profilesPath: root.path);

    expect(result.processRules.targetFor('ru.ozon.app.android'), 'DIRECT');
  });
}
