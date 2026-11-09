import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

Future<T> decodeJSONTask<T>(String data) async {
  return compute<String, T>(_decodeJSON, data);
}

Future<T> _decodeJSON<T>(String content) async {
  return json.decode(content);
}

Future<String> encodeYamlTask<T>(T data) async {
  return compute<T, String>(_encodeYaml, data);
}

Future<String> _encodeYaml<T>(T content) async {
  return yaml.encode(content);
}

/// Throws [FormatException] when the file is not UTF-8.
Future<String?> readTextFileTask(String path) {
  return compute(_readTextFile, path);
}

String? _readTextFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return utf8.decode(file.readAsBytesSync());
}

Future<List<Group>> toGroupsTask(ComputeGroupsState data) async {
  return compute<ComputeGroupsState, List<Group>>(buildGroups, data);
}

@visibleForTesting
Future<List<Group>> buildGroups(ComputeGroupsState state) async {
  final proxiesData = state.proxiesData;
  final all = proxiesData.all;
  final sortType = state.sortType;
  final delayMap = state.delayMap;
  final selectedMap = state.selectedMap;
  final defaultTestUrl = state.defaultTestUrl;
  final proxies = proxiesData.proxies;
  if (proxies.isEmpty) return [];
  final groups = <Group>[];
  for (final groupName in all) {
    final raw = proxies[groupName];
    if (raw is! Map) continue;
    if (!GroupTypeExtension.valueList.contains(raw['type'])) continue;
    final memberNames = raw['all'];
    final group = Map<String, dynamic>.from(raw);
    group['all'] = memberNames is List
        ? memberNames.map((name) => proxies[name]).nonNulls.toList()
        : const [];
    groups.add(Group.fromJson(group));
  }
  return computeSort(
    groups: groups,
    sortType: sortType,
    delayMap: delayMap,
    selectedMap: selectedMap,
    defaultTestUrl: defaultTestUrl,
  );
}

Future<ClashConfig> clashConfigTask(Map<String, dynamic> data) async {
  return compute<Map<String, dynamic>, ClashConfig>(_buildClashConfig, data);
}

ClashConfig _buildClashConfig(Map<String, dynamic> configMap) {
  return ClashConfig.fromJson(configMap);
}

typedef ConfigCounts = ({int groups, int proxies, int rules});

typedef RealProfile = ({
  String yaml,
  String md5,
  ConfigCounts counts,

  /// Where the profile's own `PROCESS-NAME*` rules send the apps, in order.
  ProcessRules processRules,
});

/// Counts what the Core was handed, not what the profile file declares.
ConfigCounts configCountsOf(Map<Object?, Object?> config) {
  int lengthOf(Object? value) => value is List ? value.length : 0;
  return (
    groups: lengthOf(config['proxy-groups']),
    proxies: lengthOf(config['proxies']),
    rules: lengthOf(config['rules']),
  );
}

String? lastMatchTarget(List<String> rules) {
  for (int i = rules.length - 1; i >= 0; i--) {
    final parsed = Rule.parse(rules[i]);
    if (parsed.ruleAction == RuleAction.MATCH) {
      final target = parsed.ruleTarget;
      if (target != null && target.isNotEmpty) {
        return target;
      }
    }
  }
  return null;
}

/// How a process rule names an app: by package, by a regular expression over
/// the package, or by a wildcard pattern over it.
enum ProcessRuleKind { name, regex, wildcard }

/// One `PROCESS-NAME*` rule of the profile, in the order the Core tries it.
@immutable
class ProcessRuleEntry {
  const ProcessRuleEntry(this.kind, this.pattern, this.target);

  const ProcessRuleEntry.name(this.pattern, this.target)
    : kind = ProcessRuleKind.name;

  const ProcessRuleEntry.regex(this.pattern, this.target)
    : kind = ProcessRuleKind.regex;

  const ProcessRuleEntry.wildcard(this.pattern, this.target)
    : kind = ProcessRuleKind.wildcard;

  final ProcessRuleKind kind;
  final String pattern;
  final String target;

  bool get targetsDirect => target == RuleTarget.DIRECT.value;

  /// The Core's semantics: an exact name and a regex ignore case, and a
  /// wildcard matches `*` and `?` on a lowercased pair.
  bool matches(String packageName) {
    switch (kind) {
      case ProcessRuleKind.name:
        return pattern.toLowerCase() == packageName.toLowerCase();
      case ProcessRuleKind.regex:
        return _processRegex(pattern)?.hasMatch(packageName) ?? false;
      case ProcessRuleKind.wildcard:
        return _processWildcard(pattern).hasMatch(packageName);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessRuleEntry &&
      other.kind == kind &&
      other.pattern == pattern &&
      other.target == target;

  @override
  int get hashCode => Object.hash(kind, pattern, target);
}

final _processRegexCache = <String, RegExp?>{};
final _processWildcardCache = <String, RegExp>{};

RegExp? _processRegex(String pattern) {
  return _processRegexCache.putIfAbsent(pattern, () {
    try {
      // The Core compiles every process regex with IgnoreCase.
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  });
}

/// `*` takes any run of characters and `?` exactly one, anchored and case
/// blind, as the Core's wildcard matcher does.
RegExp _processWildcard(String pattern) {
  return _processWildcardCache.putIfAbsent(pattern, () {
    final source = StringBuffer('^');
    for (final rune in pattern.runes) {
      switch (String.fromCharCode(rune)) {
        case '*':
          source.write('.*');
        case '?':
          source.write('.');
        case final char:
          source.write(RegExp.escape(char));
      }
    }
    source.write(r'$');
    return RegExp(source.toString(), caseSensitive: false);
  });
}

/// The process rules of a profile, in the order the Core applies them: the
/// first rule that matches an app picks its target.
@immutable
class ProcessRules {
  const ProcessRules(this.entries);

  const ProcessRules.empty() : entries = const [];

  /// The exact-name rules of a package-to-target map, for callers that hold
  /// no profile rules.
  factory ProcessRules.names(Map<String, String> targets) {
    return ProcessRules(
      List.unmodifiable([
        for (final entry in targets.entries)
          ProcessRuleEntry.name(entry.key, entry.value.toUpperCase()),
      ]),
    );
  }

  final List<ProcessRuleEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// Whether an app is named by a pattern rather than by its package, which
  /// takes the installed app list to resolve.
  bool get hasPatterns =>
      entries.any((entry) => entry.kind != ProcessRuleKind.name);

  String? targetFor(String packageName) {
    for (final entry in entries) {
      if (entry.matches(packageName)) {
        return entry.target;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessRules && listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

typedef ResolveProcessRulesState = ({
  List<String> rules,
  Object? ruleProviders,
  String? profilesPath,
  int? profileId,
});

Future<ProcessRules> resolveProcessRulesTask(ResolveProcessRulesState data) {
  return compute<ResolveProcessRulesState, ProcessRules>(
    _resolveProcessRules,
    data,
  );
}

ProcessRules _resolveProcessRules(ResolveProcessRulesState data) {
  return resolveProcessRules(
    data.rules,
    ruleProviders: data.ruleProviders,
    profilesPath: data.profilesPath,
    profileId: data.profileId,
  );
}

/// The process rules a profile's own `rules` apply, first match wins as the
/// Core gives them. A classical rule-set carries such lines for the set's own
/// target, and a downloaded set is read from the file the Core parses, with
/// its `payload` as the fallback the Core also keeps. FlClash reads it to
/// exclude the apps the profile sends DIRECT from the tunnel itself: a rule
/// inside the Core only picks the exit, while the app still sees the VPN
/// interfaces.
ProcessRules resolveProcessRules(
  List<String> rules, {
  Object? ruleProviders,
  String? profilesPath,
  int? profileId,
}) {
  final entries = <ProcessRuleEntry>[];
  final providers = ruleProviders is Map ? ruleProviders : const {};
  for (final value in rules) {
    final rule = Rule.parse(value);
    final kind = switch (rule.ruleAction) {
      RuleAction.PROCESS_NAME => ProcessRuleKind.name,
      RuleAction.PROCESS_NAME_REGEX => ProcessRuleKind.regex,
      RuleAction.PROCESS_NAME_WILDCARD => ProcessRuleKind.wildcard,
      _ => null,
    };
    if (kind != null) {
      _addProcessRule(entries, kind, rule.content, rule.ruleTarget);
      continue;
    }
    if (rule.ruleAction != RuleAction.RULE_SET) {
      continue;
    }
    final name = rule.ruleProvider;
    final provider = name == null ? null : providers[name];
    if (name == null ||
        provider is! Map ||
        provider['behavior'] != 'classical') {
      continue;
    }
    for (final line in _classicalRules(
      name,
      provider,
      profilesPath,
      profileId,
    )) {
      final innerKind = _setLineKind(line);
      if (innerKind == null) {
        continue;
      }
      // The set hands its lines to the Core with the RULE-SET's own target.
      _addProcessRule(
        entries,
        innerKind,
        _setLinePattern(line, innerKind),
        rule.ruleTarget,
      );
    }
  }
  return entries.isEmpty
      ? const ProcessRules.empty()
      : ProcessRules(List.unmodifiable(entries));
}

/// A classical set line carries no target: the Core reads it with
/// `needTarget` off, and the set's own target applies to every line.
ProcessRuleKind? _setLineKind(String line) {
  final type = line.split(',').first.trim().toUpperCase();
  return switch (type) {
    'PROCESS-NAME' => ProcessRuleKind.name,
    'PROCESS-NAME-REGEX' => ProcessRuleKind.regex,
    'PROCESS-NAME-WILDCARD' => ProcessRuleKind.wildcard,
    _ => null,
  };
}

String? _setLinePattern(String line, ProcessRuleKind kind) {
  final fields = line.split(',').map((item) => item.trim()).toList();
  if (fields.length < 2) {
    return null;
  }
  // A regex may hold commas of its own; the other kinds take one field.
  return kind == ProcessRuleKind.regex
      ? fields.sublist(1).join(',')
      : fields[1];
}

void _addProcessRule(
  List<ProcessRuleEntry> entries,
  ProcessRuleKind kind,
  String? pattern,
  String? target,
) {
  final name = pattern?.trim();
  final value = target?.trim();
  if (name == null || name.isEmpty || value == null || value.isEmpty) {
    return;
  }
  // A later rule for the same pattern can never win, so it is dropped here.
  final known = entries.any(
    (entry) => entry.kind == kind && entry.pattern == name,
  );
  if (known) {
    return;
  }
  entries.add(ProcessRuleEntry(kind, name, value.toUpperCase()));
}

/// Where FlClash keeps a provider's own file: a hash of its name and URL under
/// the profile's directory, the key `confineProviders` writes as `path`.
String providerFilePath({
  required String profilesPath,
  required int profileId,
  required String type,
  required String key,
}) {
  return join(
    profilesPath,
    providersDirectoryName,
    profileId.toString(),
    type,
    key.toMd5(),
  );
}

String? _ruleProviderPath(
  String name,
  Map provider,
  String? profilesPath,
  int? profileId,
) {
  if (profilesPath != null && profileId != null) {
    final url = provider['url'];
    final hasUrl = url is String && url.isNotEmpty;
    final confined = providerFilePath(
      profilesPath: profilesPath,
      profileId: profileId,
      type: rulesProviderDirectoryName,
      key: hasUrl ? '$name@$url' : 'rule-providers/$name',
    );
    if (File(confined).existsSync()) {
      return confined;
    }
    // A file the rename of the legacy url-only key left behind.
    if (hasUrl) {
      final legacy = providerFilePath(
        profilesPath: profilesPath,
        profileId: profileId,
        type: rulesProviderDirectoryName,
        key: url,
      );
      if (File(legacy).existsSync()) {
        return legacy;
      }
    }
  }
  // An app-level provider keeps its own path: the setup injects it after the
  // confinement pass.
  final path = provider['path'];
  if (path is String && path.isNotEmpty && File(path).existsSync()) {
    return path;
  }
  return null;
}

// A set naming every app on the phone is a couple of hundred kilobytes; the
// cap only keeps a mislabelled binary or a giant dump out of memory.
const _processRuleFileLimit = 4 << 20;

String? _readProviderText(File file) {
  try {
    if (file.lengthSync() > _processRuleFileLimit) {
      return null;
    }
    final bytes = file.readAsBytesSync();
    final body =
        bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? bytes.sublist(3)
        : bytes;
    return utf8.decode(body);
  } catch (_) {
    return null;
  }
}

/// A non-MRS set is a YAML `payload`/`rules` list or plain lines, the two
/// shapes the Core reads.
Iterable<String> _rulesFromSetText(String text) sync* {
  Object? document;
  try {
    document = loadPlainYaml(text);
  } catch (_) {
    document = null;
  }
  if (document is Map) {
    final payload = document['rules'] ?? document['payload'];
    if (payload is List) {
      yield* _cleanRuleLines(payload.whereType<String>());
      return;
    }
  } else if (document is List) {
    yield* _cleanRuleLines(document.whereType<String>());
    return;
  }
  yield* _cleanRuleLines(text.split('\n'));
}

Iterable<String> _cleanRuleLines(Iterable<String> lines) sync* {
  for (final raw in lines) {
    var line = raw.trim();
    if (line.startsWith('- ')) {
      line = line.substring(2).trim();
    }
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
      continue;
    }
    if (line.length > 1 &&
        ((line.startsWith("'") && line.endsWith("'")) ||
            (line.startsWith('"') && line.endsWith('"')))) {
      line = line.substring(1, line.length - 1);
    }
    if (line.isNotEmpty) {
      yield line;
    }
  }
}

Iterable<String> _classicalRules(
  String name,
  Map provider,
  String? profilesPath,
  int? profileId,
) sync* {
  // MRS carries domains or addresses only, never rule lines.
  if (provider['format'] == 'mrs') {
    return;
  }
  if (provider['type'] != 'inline') {
    final path = _ruleProviderPath(name, provider, profilesPath, profileId);
    if (path != null) {
      final text = _readProviderText(File(path));
      if (text != null) {
        yield* _rulesFromSetText(text);
        return;
      }
    }
  }
  final payload = provider['payload'];
  if (payload is List) {
    yield* _cleanRuleLines(payload.whereType<String>());
  }
}

Future<RealProfile> makeRealProfileTask(MakeRealProfileState data) async {
  return compute<MakeRealProfileState, RealProfile>(_makeRealProfileTask, data);
}

Future<RealProfile> _makeRealProfileTask(MakeRealProfileState data) async {
  final rawConfig = Map.from(data.rawConfig);
  final realPatchConfig = data.realPatchConfig;
  final profilesPath = data.profilesPath;
  final profileId = data.profileId;
  final overrides = data.overrides;
  final addedRules = data.addedRules;
  final appendSystemDns = data.appendSystemDns;
  final defaultUA = data.defaultUA;
  String getProvidersFilePathInner(String type, String key) {
    return providerFilePath(
      profilesPath: profilesPath,
      profileId: profileId,
      type: type,
      key: key,
    );
  }

  void confineProviders(String section, String type) {
    final providers = rawConfig[section];
    if (providers is! Map) {
      return;
    }
    for (final name in providers.keys) {
      final provider = providers[name];
      if (provider is! Map || provider['type'] == 'inline') {
        continue;
      }
      // Two providers may share a URL and differ only by header.
      final url = provider['url'];
      final hasUrl = url is String && url.isNotEmpty;
      final path = getProvidersFilePathInner(
        type,
        hasUrl ? '$name@$url' : '$section/$name',
      );
      if (hasUrl) {
        _migrateLegacyProviderFile(
          legacyPath: getProvidersFilePathInner(type, url),
          newPath: path,
        );
      }
      provider['path'] = path;
    }
  }

  rawConfig['external-controller'] =
      data.safeMode || realPatchConfig.secret.isEmpty
      ? ''
      : realPatchConfig.externalController.value;
  rawConfig['secret'] = realPatchConfig.secret;
  // mihomo serves the unix and pipe controllers without a secret, and the unix
  // one unlinks whatever sits at its path before opening it to everyone.
  rawConfig['external-controller-tls'] = '';
  rawConfig['external-controller-unix'] = '';
  rawConfig['external-controller-pipe'] = '';
  final iptables = rawConfig['iptables'];
  if (iptables is Map) {
    final inboundInterface = iptables['inbound-interface'];
    if (inboundInterface is String && inboundInterface.contains(' ')) {
      rawConfig['iptables'] = {'enable': false};
    }
  }
  rawConfig['external-ui'] = '';
  switch (realPatchConfig.interfaceNameMode) {
    case InterfaceNameMode.clear:
      rawConfig['interface-name'] = '';
    case InterfaceNameMode.follow:
      break;
    case InterfaceNameMode.custom:
      rawConfig['interface-name'] = realPatchConfig.interfaceName;
  }
  rawConfig['external-ui-url'] = '';
  // find-process-mode is not forced: a picked override key writes it
  // above, and otherwise the profile's own process configuration wins.
  rawConfig.addAll(realPatchConfig.generalOverrideJson);
  rawConfig['log-level'] = realPatchConfig.logLevel.name;
  rawConfig['port'] = 0;
  rawConfig['socks-port'] = 0;
  rawConfig['keep-alive-interval'] = realPatchConfig.keepAliveInterval;
  rawConfig['keep-alive-idle'] = realPatchConfig.keepAliveIdle;
  rawConfig['disable-keep-alive'] = realPatchConfig.disableKeepAlive;
  rawConfig['routing-mark'] = realPatchConfig.routingMark;
  rawConfig['mixed-port'] = realPatchConfig.mixedPort;
  rawConfig['port'] = realPatchConfig.port;
  rawConfig['socks-port'] = realPatchConfig.socksPort;
  rawConfig['redir-port'] = realPatchConfig.redirPort;
  rawConfig['tproxy-port'] = realPatchConfig.tproxyPort;
  rawConfig['allow-lan'] = realPatchConfig.allowLan;
  // The app owns local inbound authentication; a profile-provided
  // skip-auth-prefixes could silently exempt loopback and defeat it.
  rawConfig['authentication'] = data.authentication;
  rawConfig['skip-auth-prefixes'] = [];
  rawConfig['mode'] = realPatchConfig.mode.name;
  // auto-route is always on, so without auto-detect-interface the core sends
  // its own outbound back into the TUN unless interface-name binds it, and
  // interface-name wins over the detected interface anyway. A profile's own
  // dns-hijack may leave queries to other resolvers unhijacked, so only a
  // picked key replaces any:53.
  final tun = {
    if (rawConfig['tun'] is Map) ...rawConfig['tun'] as Map,
    'dns-hijack': defaultDnsHijack,
    ...overrides.tun.overrideJson(overrides.tunOverrideKeys),
    ...realPatchConfig.tun.coreJson,
    'auto-detect-interface': true,
  };
  if (data.bypassPrivateRoute) {
    tun['route-exclude-address'] = [
      if (tun['route-exclude-address'] case final List routes) ...routes,
      ...privateRouteAddress,
    ];
  }
  rawConfig['tun'] = tun;
  rawConfig['geo-auto-update'] = realPatchConfig.geoAutoUpdate;
  rawConfig['geo-update-interval'] = realPatchConfig.geoUpdateInterval;
  final snifferOverride = overrides.sniffer.overrideJson(
    overrides.snifferOverrideKeys,
  );
  if (snifferOverride.isNotEmpty) {
    rawConfig['sniffer'] = mergeSnifferOverride(
      rawConfig['sniffer'] is Map
          ? Map<String, dynamic>.from(rawConfig['sniffer'] as Map)
          : <String, dynamic>{},
      snifferOverride,
    );
  }
  if (rawConfig['sniffer']?['sniff'] != null) {
    for (final value in (rawConfig['sniffer']?['sniff'] as Map).values) {
      if (value['ports'] != null && value['ports'] is List) {
        value['ports'] =
            value['ports']?.map((item) => item.toString()).toList() ?? [];
      }
    }
  }
  if (rawConfig['profile'] == null) {
    rawConfig['profile'] = {};
  }
  void injectUnconfinedProviders(
    String section,
    Map<String, dynamic> injected,
  ) {
    if (injected.isEmpty) {
      return;
    }
    final providers = rawConfig[section];
    rawConfig[section] = {
      ...injected,
      if (providers is Map) ...providers.cast<String, dynamic>(),
    };
  }

  confineProviders('proxy-providers', proxiesProviderDirectoryName);
  confineProviders('rule-providers', rulesProviderDirectoryName);
  injectUnconfinedProviders('proxy-providers', data.injectedProxyProviders);
  injectUnconfinedProviders('rule-providers', data.injectedRuleProviders);
  rawConfig['profile']['store-selected'] = false;
  rawConfig['geox-url'] = realPatchConfig.geoXUrl.raw;
  rawConfig['global-ua'] = realPatchConfig.globalUa ?? defaultUA;
  if (rawConfig['hosts'] == null) {
    rawConfig['hosts'] = {};
  }
  for (final host in realPatchConfig.hosts.entries) {
    rawConfig['hosts'][host.key] = host.value.splitByMultipleSeparators;
  }
  var rawDns = rawConfig['dns'] is Map
      ? Map<String, dynamic>.from(rawConfig['dns'] as Map)
      : <String, dynamic>{};
  final isEnableDns = rawDns['enable'] == true;
  const systemDns = 'system://';
  if (!isEnableDns) {
    rawDns = mergeDnsOverride(
      rawDns,
      baselineDns.overrideJson(baselineDnsOverrideKeys),
    );
  }
  rawDns = mergeDnsOverride(
    rawDns,
    overrides.dns.overrideJson(
      overrides.dnsOverrideKeys,
      keepEmpty: data.keepEmptyDnsOverrides,
    ),
  );
  rawConfig['dns'] = rawDns;
  final ntpOverride = overrides.ntp.overrideJson(overrides.ntpOverrideKeys);
  if (ntpOverride.isNotEmpty) {
    final rawNtp = rawConfig['ntp'] is Map
        ? Map<String, dynamic>.from(rawConfig['ntp'] as Map)
        : <String, dynamic>{};
    rawConfig['ntp'] = {...rawNtp, ...ntpOverride};
  }
  if (appendSystemDns) {
    final List<String> nameserver = List<String>.from(
      rawConfig['dns']['nameserver'] ?? [],
    );
    if (!nameserver.contains(systemDns)) {
      rawConfig['dns']['nameserver'] = [...nameserver, systemDns];
    }
  }
  if (data.safeMode) {
    rawConfig['listeners'] = [];
    rawConfig['tunnels'] = [];
    rawConfig['ss-config'] = '';
    rawConfig['vmess-config'] = '';
    rawConfig['tuic-server'] = {'enable': false};
    rawConfig['iptables'] = {'enable': false};
    rawConfig['dns']['listen'] = '';
    final rawNtp = rawConfig['ntp'];
    if (rawNtp is Map) {
      rawConfig['ntp'] = {
        ...Map<String, dynamic>.from(rawNtp),
        NtpOverrideKey.writeToSystem.path: false,
      };
    }
  }
  List<String> rules = [];
  if (data.rules.isEmpty) {
    if (rawConfig['rules'] != null) {
      rules = List<String>.from(rawConfig['rules']);
    }
    if (addedRules.isNotEmpty) {
      final hasMatchPlaceholder = addedRules.any(
        (item) => item.ruleTarget?.toUpperCase() == 'MATCH',
      );
      String? replacementTarget = data.matchTarget?.trim();
      if (replacementTarget?.isEmpty == true) {
        replacementTarget = null;
      }

      if (hasMatchPlaceholder && replacementTarget == null) {
        replacementTarget = lastMatchTarget(rules);
      }
      final List<String> finalAddedRules;

      if (replacementTarget?.isNotEmpty == true) {
        finalAddedRules = [];
        for (int i = 0; i < addedRules.length; i++) {
          final parsed = addedRules[i];
          if (parsed.ruleTarget?.toUpperCase() == 'MATCH') {
            finalAddedRules.add(
              parsed.copyWith(ruleTarget: replacementTarget).rawValue,
            );
          } else {
            finalAddedRules.add(addedRules[i].rawValue);
          }
        }
      } else {
        finalAddedRules = addedRules.map((e) => e.rawValue).toList();
      }
      rules = [...finalAddedRules, ...rules];
    }
  } else {
    rules = data.rules.map((item) => item.rawValue).toList();
  }
  if (data.proxyGroups.isNotEmpty) {
    rawConfig['proxy-groups'] = data.proxyGroups
        .map((item) => item.definition)
        .toList();
  }
  rawConfig['rules'] = rules;
  final yaml = await _encodeYaml(Map<String, dynamic>.from(rawConfig));
  return (
    yaml: yaml,
    md5: yaml.toMd5(),
    counts: configCountsOf(rawConfig),
    processRules: resolveProcessRules(
      rules,
      ruleProviders: rawConfig['rule-providers'],
      profilesPath: profilesPath,
      profileId: profileId,
    ),
  );
}

typedef ShakingStoreArgs = ({
  Iterable<int> profileIds,
  Iterable<int> scriptIds,
  Iterable<String> providerFileNames,
});

Future<List<String>> shakingProfileTask(ShakingStoreArgs data) async {
  return compute<
    ({ShakingStoreArgs args, RootIsolateToken token}),
    List<String>
  >(_shakingProfileTask, (args: data, token: RootIsolateToken.instance!));
}

Future<List<String>> _shakingProfileTask(
  ({ShakingStoreArgs args, RootIsolateToken token}) data,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(data.token);
  return shakeOrphanFiles(
    profileIds: data.args.profileIds,
    scriptIds: data.args.scriptIds,
    providerFileNames: data.args.providerFileNames,
    profilesDirPath: await appPath.profilesPath,
    providersDirPath: await appPath.getProvidersRootPath(),
    providerCacheDirPath: await appPath.providerCacheRootPath,
    scriptsDirPath: await appPath.scriptsDirPath,
  );
}

@visibleForTesting
List<String> shakeOrphanFiles({
  required Iterable<int> profileIds,
  required Iterable<int> scriptIds,
  required Iterable<String> providerFileNames,
  required String profilesDirPath,
  required String providersDirPath,
  required String providerCacheDirPath,
  required String scriptsDirPath,
}) {
  final List<String> targets = [];
  void scanDirectory(
    Directory dir,
    bool Function(String baseName) isLive, {
    bool includeDirectories = false,
  }) {
    if (!dir.existsSync()) return;
    final entities = dir.listSync(recursive: false, followLinks: false);

    for (final entity in entities) {
      final selected =
          entity is File || (includeDirectories && entity is Directory);
      if (!selected) {
        continue;
      }
      if (!isLive(basenameWithoutExtension(entity.path))) {
        targets.add(entity.path);
      }
    }
  }

  bool Function(String) isLiveId(Iterable<int> ids) =>
      (baseName) => ids.contains(int.tryParse(baseName));

  scanDirectory(Directory(profilesDirPath), isLiveId(profileIds));
  scanDirectory(
    Directory(providersDirPath),
    isLiveId(profileIds),
    includeDirectories: true,
  );
  scanDirectory(
    Directory(join(providerCacheDirPath, rulesProviderDirectoryName)),
    providerFileNames.toSet().contains,
  );
  scanDirectory(Directory(scriptsDirPath), isLiveId(scriptIds));
  return targets;
}

// Best-effort: a legacy url shared by two providers, or any rename failure,
// just leaves the file to be re-downloaded under the new path.
void _migrateLegacyProviderFile({
  required String legacyPath,
  required String newPath,
}) {
  if (legacyPath == newPath || File(newPath).existsSync()) {
    return;
  }
  try {
    final legacyFile = File(legacyPath);
    if (legacyFile.existsSync()) {
      Directory(dirname(newPath)).createSync(recursive: true);
      legacyFile.renameSync(newPath);
    }
  } catch (_) {}
}

Future<String> encodeLogsTask(List<Log> data) async {
  return compute<List<Log>, String>(_encodeLogsTask, data);
}

Future<String> _encodeLogsTask(List<Log> data) async {
  final logsRaw = data.map((item) => item.toString());
  final logsRawString = logsRaw.join('\n');
  return logsRawString;
}

Future<MigrationData> oldToNowTask(Map<String, Object?> data) async {
  final homeDir = await appPath.homeDirPath;
  return compute<
    ({Map<String, Object?> configMap, String sourcePath, String targetPath}),
    MigrationData
  >(_oldToNowTask, (configMap: data, sourcePath: homeDir, targetPath: homeDir));
}

Future<MigrationData> _oldToNowTask(
  ({Map<String, Object?> configMap, String sourcePath, String targetPath}) data,
) {
  return migrateLegacyConfig(
    configMap: data.configMap,
    sourcePath: data.sourcePath,
    targetPath: data.targetPath,
  );
}

Future<MigrationData> migrateLegacyConfig({
  required Map<String, Object?> configMap,
  required String sourcePath,
  required String targetPath,
}) async {
  final accessControlMap = configMap['accessControl'];
  final isAccessControl = configMap['isAccessControl'];
  if (accessControlMap != null) {
    (accessControlMap as Map)['enable'] = isAccessControl;
    if (configMap['vpnProps'] != null) {
      final vpnPropsRaw = configMap['vpnProps'] as Map;
      vpnPropsRaw['accessControl'] = accessControlMap;
    }
  }
  if (configMap['vpnProps'] != null) {
    final vpnPropsRaw = configMap['vpnProps'] as Map;
    vpnPropsRaw['accessControlProps'] = vpnPropsRaw['accessControl'];
  }
  configMap['davProps'] = configMap['dav'];
  final appSettingProps =
      configMap['appSetting'] as Map<String, dynamic>? ?? {};
  appSettingProps['restoreStrategy'] = appSettingProps['recoveryStrategy'];
  configMap['appSettingProps'] = appSettingProps;
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  List rawScripts = configMap['scripts'] as List<dynamic>? ?? [];
  if (rawScripts.isEmpty) {
    final scriptPropsJson = configMap['scriptProps'] as Map<String, dynamic>?;
    if (scriptPropsJson != null) {
      rawScripts = scriptPropsJson['scripts'] as List<dynamic>? ?? [];
    }
  }
  final Map<String, int> idMap = {};
  final List<Script> scripts = [];
  for (final rawScript in rawScripts) {
    final id = rawScript['id'] as String?;
    final content = rawScript['content'] as String?;
    final label = rawScript['label'] as String?;
    if (id == null || content == null || label == null) {
      continue;
    }
    final newId = idMap.updateCacheValue(rawScript['id'], () => snowflake.id);
    final path = BackupEntries.resolve(targetPath, BackupEntries.script(newId));
    final file = File(path);
    await file.safeWriteAsString(content);
    scripts.add(
      Script(id: newId, label: label, lastUpdateTime: DateTime.now()),
    );
  }
  final List rawRules = configMap['rules'] as List<dynamic>? ?? [];
  final List<Rule> rules = [];
  final List<DisabledRule> disabledRules = [];
  for (final rawRule in rawRules) {
    final id = idMap.updateCacheValue(rawRule['id'], () => snowflake.id);
    rawRule['id'] = id;
    final value = rawRule['value'] ?? '';
    rules.add(Rule.parse(value, id: id));
  }
  final List rawProfiles = configMap['profiles'] as List<dynamic>? ?? [];
  final List<Profile> profiles = [];
  for (final rawProfile in rawProfiles) {
    final rawId = rawProfile['id'] as String?;
    if (rawId == null) {
      continue;
    }
    final profileId = idMap.updateCacheValue(rawId, () => snowflake.id);
    rawProfile['id'] = profileId;
    final overwrite = rawProfile['overwrite'] as Map?;
    if (overwrite != null) {
      final standardOverwrite = overwrite['standardOverwrite'] as Map?;
      if (standardOverwrite != null) {
        final addedRules = standardOverwrite['addedRules'] as List? ?? [];
        for (final addRule in addedRules) {
          final id = idMap.updateCacheValue(addRule['id'], () => snowflake.id);
          final value = addRule['value'] ?? '';
          rules.add(Rule.parse(value, id: id).copyWith(profileId: profileId));
        }
        final disabledRuleIds = standardOverwrite['disabledRuleIds'] as List?;
        if (disabledRuleIds != null) {
          for (final disabledRuleId in disabledRuleIds) {
            final newDisabledRuleId = idMap[disabledRuleId];
            if (newDisabledRuleId != null) {
              disabledRules.add(
                DisabledRule(profileId: profileId, ruleId: newDisabledRuleId),
              );
            }
          }
        }
      }
      final scriptOverwrite = overwrite['scriptOverwrite'] as Map?;
      if (scriptOverwrite != null) {
        final scriptId = scriptOverwrite['scriptId'] as String?;
        rawProfile['scriptId'] = scriptId != null ? idMap[scriptId] : null;
      }
      rawProfile['extendType'] = overwrite['type'] == ExtendType.script.name
          ? ExtendType.script.name
          : ExtendType.standard.name;
    }
    final rawUrl = rawProfile['url'];
    rawProfile['type'] = rawUrl is String && rawUrl.isNotEmpty ? 'url' : 'file';

    final sourceFile = File(
      BackupEntries.resolve(sourcePath, BackupEntries.profile(rawId)),
    );
    final targetFilePath = BackupEntries.resolve(
      targetPath,
      BackupEntries.profile(profileId),
    );
    await sourceFile.safeCopy(targetFilePath);
    profiles.add(Profile.fromJson(rawProfile));
  }
  final currentProfileId = configMap['currentProfileId'];
  configMap['currentProfileId'] = currentProfileId != null
      ? idMap[currentProfileId]
      : null;
  return MigrationData(
    configMap: configMap,
    profiles: profiles,
    rules: rules,
    scripts: scripts,
    disabledRules: disabledRules,
  );
}
