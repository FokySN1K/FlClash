import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_targets.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/views/dashboard/widgets/route_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

const _quality = IpQuality(
  ip: '203.0.113.7',
  source: IpQualitySource.ipLocate,
  type: IpType.residential,
);

/// Answers from a fixed cache and holds no watchers, so the rows show what
/// the map makes of each answer rather than what a probe would fetch.
class _Ips extends OutboundIpProbe {
  @override
  RoutedProbeState<String, IpInfo> build() => const RoutedProbeState({
    'DIRECT': ProbeEntry(
      phase: ProbePhase.fresh,
      value: IpInfo(ip: '198.51.100.4', countryCode: 'RU'),
    ),
    'Proxy': ProbeEntry(
      phase: ProbePhase.fresh,
      value: IpInfo(ip: '203.0.113.7', countryCode: 'NL'),
    ),
  });

  @override
  void watch(String target) {}

  @override
  void unwatch(String target) {}
}

Widget _app(List<RouteTarget> targets) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      outboundIpProbeProvider.overrideWith(_Ips.new),
      routeTargetsProvider.overrideWith((ref) async => targets),
      ipQualityProvider.overrideWith((ref, ip) async => _quality),
    ],
    child: Scaffold(body: ListView(children: const [RouteMapSection()])),
  );
}

void main() {
  testWidgets('shows an address for every outbound the rules name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const [
        RouteTarget(name: 'DIRECT', rules: 2),
        RouteTarget(name: 'Proxy', rules: 5, isDefault: true),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Exit nodes'), findsOneWidget);
    expect(find.text('198.51.100.4'), findsOneWidget);
    expect(find.text('203.0.113.7'), findsOneWidget);
    expect(find.text('2 rules · Residential · Good'), findsOneWidget);
    expect(find.text('Default · 5 rules · Residential · Good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says a target it could not reach has no address', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const [RouteTarget(name: 'Fallback', rules: 1)]),
    );
    await tester.pump();

    expect(find.text('Fallback'), findsOneWidget);
    expect(find.text('No info'), findsOneWidget);
    expect(find.text('1 rule'), findsOneWidget);
  });

  testWidgets('stays away while the Core lists nothing', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pump();

    expect(find.text('Exit nodes'), findsNothing);
  });
}
