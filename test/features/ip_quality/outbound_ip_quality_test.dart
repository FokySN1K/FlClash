import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

const _quality = IpQuality(
  ip: '203.0.113.7',
  source: IpQualitySource.ipLocate,
  type: IpType.residential,
  organization: 'Example Broadband',
  asn: 64500,
);

class _Ips extends OutboundIpProbe {
  @override
  RoutedProbeState<String, IpInfo> build() => const RoutedProbeState({
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

Widget _app(
  String target, {
  Future<IpQuality> Function(Ref ref, String ip) lookup = _lookup,
}) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      outboundIpProbeProvider.overrideWith(_Ips.new),
      ipQualityProvider.overrideWith(lookup),
    ],
    child: Scaffold(
      body: ListView(children: [OutboundIpQualitySection(target: target)]),
    ),
  );
}

Future<IpQuality> _lookup(Ref ref, String ip) async => _quality;

void main() {
  testWidgets('describes the address the node leaves by', (tester) async {
    await tester.pumpWidget(_app('Proxy'));
    await tester.pump();

    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Residential'), findsOneWidget);
    expect(find.text('Example Broadband'), findsOneWidget);
    expect(find.text('AS64500'), findsOneWidget);
    expect(find.text('Flags'), findsNothing);
  });

  testWidgets('lists a flag the address carries', (tester) async {
    await tester.pumpWidget(
      _app('Proxy', lookup: (ref, ip) async => _quality.copyWith(isTor: true)),
    );
    await tester.pump();

    expect(find.text('Flags'), findsOneWidget);
    expect(find.text('Tor'), findsOneWidget);
    expect(find.text('Risky'), findsOneWidget);
  });

  testWidgets('stays away until the address is known', (tester) async {
    await tester.pumpWidget(_app('Fallback'));
    await tester.pump();

    expect(find.text('Quality'), findsNothing);
  });

  testWidgets('waits for the quality to arrive', (tester) async {
    final quality = Completer<IpQuality>();
    await tester.pumpWidget(_app('Proxy', lookup: (ref, ip) => quality.future));
    await tester.pump();

    expect(find.text('Quality'), findsNothing);

    quality.complete(_quality);
    await tester.pumpAndSettle();

    expect(find.text('Quality'), findsOneWidget);
  });
}
