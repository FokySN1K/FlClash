import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/core.freezed.dart';
part 'generated/core.g.dart';

@freezed
abstract class SetupParams with _$SetupParams {
  const factory SetupParams({
    @JsonKey(name: 'selected-map') required Map<String, String> selectedMap,
    @JsonKey(name: 'test-url') required String testUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
    @JsonKey(includeIfNull: false) SetupBase? base,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class SetupBase with _$SetupBase {
  const factory SetupBase({required String path, required String overlay}) =
      _SetupBase;

  factory SetupBase.fromJson(Map<String, dynamic> json) =>
      _$SetupBaseFromJson(json);
}

@freezed
abstract class ProfileBase with _$ProfileBase {
  const factory ProfileBase({
    required Map<String, dynamic> config,
    required String digest,
    @Default([]) @JsonKey(name: 'match-rules') List<String> matchRules,

    /// The profile's own `PROCESS-NAME` and `RULE-SET` lines: the Core drops
    /// `rules` from the config it returns, so the host reads them here.
    @Default([]) @JsonKey(name: 'process-rules') List<String> processRules,
    @Default(0) int proxies,
    @Default(0) @JsonKey(name: 'proxy-groups') int proxyGroups,
    @Default(0) int rules,
  }) = _ProfileBase;

  factory ProfileBase.fromJson(Map<String, dynamic> json) =>
      _$ProfileBaseFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    @JsonKey(toJson: _tunCoreJson) required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode', includeIfNull: false)
    FindProcessMode? findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    bool? ipv6,
    @JsonKey(name: 'tcp-concurrent') bool? tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @Default('') String secret,
    @JsonKey(name: 'unified-delay') bool? unifiedDelay,
    @Default([]) List<String> authentication,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
    @Default({}) @JsonKey(name: 'geox-url') Map<String, String> geoXUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

Map<String, Object?> _tunCoreJson(Tun tun) => tun.coreJson;

@freezed
abstract class VpnOptions with _$VpnOptions {
  const factory VpnOptions({
    required bool enable,
    required int port,
    required bool ipv6,
    required bool dnsHijacking,
    required AccessControlProps accessControlProps,
    required bool allowBypass,
    required bool systemProxy,
    required List<String> bypassDomain,
    required String stack,
    @Default([]) List<String> excludePackages,
    @Default([]) List<String> routeAddress,
    @Default(0) int mtu,
    @Default('') String congestionController,
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

extension VpnOptionsExt on VpnOptions {
  /// Only what `ServiceController.start` and `VpnService.handleStart` read.
  VpnOptions get effective {
    if (!enable) {
      return const VpnOptions(
        enable: false,
        port: 0,
        ipv6: false,
        dnsHijacking: false,
        accessControlProps: AccessControlProps(),
        allowBypass: false,
        systemProxy: false,
        bypassDomain: [],
        stack: '',
      );
    }
    final accessControl = accessControlProps;
    final accepts = accessControl.mode == AccessControlMode.acceptSelected;
    return copyWith(
      port: systemProxy ? port : 0,
      bypassDomain: systemProxy ? bypassDomain : const [],
      // The switch off excludes nothing, whatever lists an older build left
      // beside it.
      excludePackages: accessControl.enable ? excludePackages : const [],
      accessControlProps: accessControl.enable
          ? AccessControlProps(
              enable: true,
              mode: accessControl.mode,
              acceptList: accepts ? accessControl.acceptList : const [],
              rejectList: accepts ? const [] : accessControl.rejectList,
            )
          : const AccessControlProps(),
    );
  }
}

@freezed
abstract class InitParams with _$InitParams {
  const factory InitParams({
    @JsonKey(name: 'home-dir') required String homeDir,
    required int version,
  }) = _InitParams;

  factory InitParams.fromJson(Map<String, Object?> json) =>
      _$InitParamsFromJson(json);
}

@freezed
abstract class ChangeProxyParams with _$ChangeProxyParams {
  const factory ChangeProxyParams({
    @JsonKey(name: 'group-name') required String groupName,
    @JsonKey(name: 'proxy-name') required String proxyName,
  }) = _ChangeProxyParams;

  factory ChangeProxyParams.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyParamsFromJson(json);
}

@freezed
abstract class ChangeProxyResult with _$ChangeProxyResult {
  const factory ChangeProxyResult({
    @Default('') String message,
    @Default(false) bool changed,
  }) = _ChangeProxyResult;

  factory ChangeProxyResult.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyResultFromJson(json);
}

@freezed
abstract class RouteSnapshot with _$RouteSnapshot {
  const factory RouteSnapshot({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
  }) = _RouteSnapshot;

  factory RouteSnapshot.fromJson(Map<String, Object?> json) =>
      _$RouteSnapshotFromJson(json);
}

/// [exit] is the Core's name for where a connection left, only compared whole.
@freezed
abstract class RouteHit with _$RouteHit {
  const factory RouteHit({
    @Default('') String host,
    @Default('') String proxy,
    @Default('') String exit,
  }) = _RouteHit;

  factory RouteHit.fromJson(Map<String, Object?> json) =>
      _$RouteHitFromJson(json);
}

/// Where the Core sent a connection, as [RouteHit.exit] spells it out:
/// `"name" type address`, the name Go-quoted because it may hold spaces.
@immutable
class RouteExit {
  const RouteExit({
    required this.name,
    required this.type,
    required this.address,
  });

  final String name;
  final String type;
  final String address;

  static RouteExit? parse(String exit) {
    final match = _exitPattern.firstMatch(exit);
    if (match == null) {
      return null;
    }
    return RouteExit(
      name: match
          .group(1)!
          .replaceAllMapped(_exitEscape, (escape) => escape[1]!),
      type: match.group(2)!,
      address: match.group(3) ?? '',
    );
  }
}

/// Go's `%q` leaves a profile's names as they are but for these two escapes.
final _exitPattern = RegExp(r'^"((?:[^"\\]|\\.)*)" (\S+)(?: (.*))?$');
final _exitEscape = RegExp(r'\\(["\\])');

extension RouteHitExt on RouteHit {
  RouteExit? get exitInfo => RouteExit.parse(exit);
}

extension RouteHitsExt on Iterable<RouteHit> {
  /// The first hit whose exit the Core spelled out in full.
  RouteExit? get exitInfo {
    for (final hit in this) {
      final exit = hit.exitInfo;
      if (exit != null && exit.name.isNotEmpty) {
        return exit;
      }
    }
    return null;
  }
}

/// One outbound the applied rules send traffic to, with the number of rules
/// that name it. [isDefault] marks the outbound unmatched traffic leaves by.
@immutable
class RouteTarget {
  const RouteTarget({
    required this.name,
    this.rules = 0,
    this.isDefault = false,
  });

  factory RouteTarget.fromJson(Map<String, Object?> json) => RouteTarget(
    name: json['name'] as String? ?? '',
    rules: (json['rules'] as num?)?.toInt() ?? 0,
    isDefault: json['default'] == true,
  );

  final String name;

  /// How many of the rules name this outbound; zero when the mode sends
  /// everything to it without asking them.
  final int rules;

  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is RouteTarget &&
      other.name == name &&
      other.rules == rules &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(name, rules, isDefault);

  @override
  String toString() => 'RouteTarget($name, rules: $rules, default: $isDefault)';
}

/// One entry of a node's check history: when the check ran and what it
/// measured. A zero [delay] is a check that failed.
@immutable
class DelaySample {
  const DelaySample({required this.time, required this.delay});

  factory DelaySample.fromJson(Map<String, Object?> json) => DelaySample(
    time: (json['time'] as num?)?.toInt() ?? 0,
    delay: (json['delay'] as num?)?.toInt() ?? 0,
  );

  /// Unix milliseconds of the check.
  final int time;

  /// What the check measured in milliseconds; zero when it failed.
  final int delay;

  DateTime get checkedAt => DateTime.fromMillisecondsSinceEpoch(time);

  @override
  bool operator ==(Object other) =>
      other is DelaySample && other.time == time && other.delay == delay;

  @override
  int get hashCode => Object.hash(time, delay);

  @override
  String toString() => 'DelaySample($time, $delay)';
}

/// The node to describe and the target its group tests against.
@immutable
class ProxyDetailsParams {
  const ProxyDetailsParams({required this.proxyName, this.testUrl = ''});

  factory ProxyDetailsParams.fromJson(Map<String, Object?> json) =>
      ProxyDetailsParams(
        proxyName: json['proxy-name'] as String? ?? '',
        testUrl: json['test-url'] as String? ?? '',
      );

  final String proxyName;
  final String testUrl;

  Map<String, Object?> toJson() => {
    'proxy-name': proxyName,
    'test-url': testUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is ProxyDetailsParams &&
      other.proxyName == proxyName &&
      other.testUrl == testUrl;

  @override
  int get hashCode => Object.hash(proxyName, testUrl);
}

/// What a card has no room for: the verdict of the last check for the group's
/// target, the checks before it, and the transports the node offers.
@immutable
class ProxyDetails {
  const ProxyDetails({
    this.alive = false,
    this.history = const [],
    this.udp = false,
    this.uot = false,
    this.xudp = false,
    this.tfo = false,
    this.mptcp = false,
    this.smux = false,
  });

  factory ProxyDetails.fromJson(Map<String, Object?> json) => ProxyDetails(
    alive: json['alive'] == true,
    history: [
      for (final item in (json['history'] as List?) ?? const [])
        if (item is Map) DelaySample.fromJson(Map<String, Object?>.from(item)),
    ],
    udp: json['udp'] == true,
    uot: json['uot'] == true,
    xudp: json['xudp'] == true,
    tfo: json['tfo'] == true,
    mptcp: json['mptcp'] == true,
    smux: json['smux'] == true,
  );

  final bool alive;
  final List<DelaySample> history;
  final bool udp;
  final bool uot;
  final bool xudp;
  final bool tfo;
  final bool mptcp;
  final bool smux;

  /// The last check the history holds; null until the node is checked.
  DelaySample? get last => history.isEmpty ? null : history.last;

  /// The transports the node offers, named the way the Core spells them.
  List<String> get transports => [
    if (udp) 'UDP',
    if (uot) 'UOT',
    if (xudp) 'XUDP',
    if (tfo) 'TFO',
    if (mptcp) 'MPTCP',
    if (smux) 'SMUX',
  ];
}

@freezed
abstract class CheckRoutesParams with _$CheckRoutesParams {
  const factory CheckRoutesParams({@Default([]) List<List<RouteHit>> routes}) =
      _CheckRoutesParams;

  factory CheckRoutesParams.fromJson(Map<String, Object?> json) =>
      _$CheckRoutesParamsFromJson(json);
}

@freezed
abstract class RouteCheck with _$RouteCheck {
  const factory RouteCheck({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<bool> held,
  }) = _RouteCheck;

  factory RouteCheck.fromJson(Map<String, Object?> json) =>
      _$RouteCheckFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class ProbeParams with _$ProbeParams {
  const factory ProbeParams({
    required String url,
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default({}) Map<String, String> headers,
    required int timeout,
    @JsonKey(name: 'max-body') @Default(0) int maxBody,
  }) = _ProbeParams;

  factory ProbeParams.fromJson(Map<String, Object?> json) =>
      _$ProbeParamsFromJson(json);
}

@freezed
abstract class ProbeResult with _$ProbeResult {
  const factory ProbeResult({
    @JsonKey(name: 'status-code') @Default(0) int statusCode,
    @Default(0) int delay,
    @Default('') String body,
    @Default('') String url,
    @Default([]) List<String> chains,
    @Default('') String rule,
    @JsonKey(name: 'rule-payload') @Default('') String rulePayload,
    String? error,
    String? message,
  }) = _ProbeResult;

  factory ProbeResult.fromJson(Map<String, Object?> json) =>
      _$ProbeResultFromJson(json);
}

@freezed
abstract class OutboundIpParams with _$OutboundIpParams {
  const factory OutboundIpParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> urls,
    required int timeout,
  }) = _OutboundIpParams;

  factory OutboundIpParams.fromJson(Map<String, Object?> json) =>
      _$OutboundIpParamsFromJson(json);
}

@freezed
abstract class OutboundIpResult with _$OutboundIpResult {
  const factory OutboundIpResult({
    @Default('') String url,
    @Default('') String body,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    String? error,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
    @JsonKey(name: 'node-hits') @Default([]) List<RouteHit> nodeHits,
  }) = _OutboundIpResult;

  factory OutboundIpResult.fromJson(Map<String, Object?> json) =>
      _$OutboundIpResultFromJson(json);
}

@freezed
abstract class ServiceCheckParams with _$ServiceCheckParams {
  const factory ServiceCheckParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> names,
    required int timeout,
  }) = _ServiceCheckParams;

  factory ServiceCheckParams.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckParamsFromJson(json);
}

@freezed
abstract class ServiceCheckItem with _$ServiceCheckItem {
  const factory ServiceCheckItem({
    @Default('') String name,
    @Default('') String status,
    @Default('') String region,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    @JsonKey(name: 'checked-at') @Default(0) int checkedAt,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
  }) = _ServiceCheckItem;

  factory ServiceCheckItem.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckItemFromJson(json);
}

@freezed
abstract class CoreMemoryStats with _$CoreMemoryStats {
  const factory CoreMemoryStats({
    @Default(0) int rss,
    @Default(0) int heapInuse,
    @Default(0) int heapIdle,
    @Default(0) int stackInuse,
    @Default(0) int runtimeOther,
  }) = _CoreMemoryStats;

  factory CoreMemoryStats.fromJson(Map<String, Object?> json) =>
      _$CoreMemoryStatsFromJson(json);
}

extension CoreMemoryStatsExt on CoreMemoryStats {
  int get runtimeTotal => heapInuse + heapIdle + stackInuse + runtimeOther;
}

SubscriptionInfo? subscriptionInfoFormCore(Map<String, Object?>? json) {
  if (json == null) return null;
  return SubscriptionInfo(
    upload: (json['Upload'] as num?)?.toInt() ?? 0,
    download: (json['Download'] as num?)?.toInt() ?? 0,
    total: (json['Total'] as num?)?.toInt() ?? 0,
    expire: (json['Expire'] as num?)?.toInt() ?? 0,
  );
}

@freezed
abstract class ExternalProvider with _$ExternalProvider {
  const factory ExternalProvider({
    required String name,
    required String type,
    String? path,
    required int count,
    @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)
    SubscriptionInfo? subscriptionInfo,
    @JsonKey(name: 'vehicle-type') required String vehicleType,
    @JsonKey(name: 'update-at') required DateTime updateAt,
  }) = _ExternalProvider;

  factory ExternalProvider.fromJson(Map<String, Object?> json) =>
      _$ExternalProviderFromJson(json);
}

extension ExternalProviderExt on ExternalProvider {
  String get updatingKey => 'provider_$name';
}

@freezed
abstract class ProxiesData with _$ProxiesData {
  const factory ProxiesData({
    required Map<String, dynamic> proxies,
    required List<String> all,
  }) = _ProxiesData;

  factory ProxiesData.fromJson(Map<String, Object?> json) =>
      _$ProxiesDataFromJson(json);
}
