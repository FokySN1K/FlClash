import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/features/proxy_details/proxy_details.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/proxy_definition.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/glyph_finders.dart';
import '../../helpers/test_app.dart';

const _name = 'HK 01';

const _uuid = '6c1f2e1a-3b1c-4b7a-9f1e-000000000001';

const _definition = <String, dynamic>{
  'name': _name,
  'type': 'vless',
  'server': 'example.com',
  'port': 443,
  'sni': 'cdn.example.com',
  'uuid': _uuid,
};

Widget _app(Widget section, {Map<String, dynamic>? definition = _definition}) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      proxyDefinitionProvider.overrideWith((_, _) async => definition),
    ],
    homeBuilder: (child) => Scaffold(body: child),
    child: section,
  );
}

void main() {
  group('the connection section', () {
    testWidgets('shows the endpoint, the SNI and a masked key', (tester) async {
      await tester.pumpWidget(_app(const ProxyConnectionSection(name: _name)));
      await tester.pump();

      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('443'), findsOneWidget);
      expect(find.text('SNI'), findsOneWidget);
      expect(find.text('cdn.example.com'), findsOneWidget);
      expect(find.text('UUID'), findsOneWidget);
      expect(find.text(_uuid), findsNothing);
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.byGlyph(AppGlyphs.eye), findsOneWidget);

      final row = tester.widget<DetailRow>(
        find.ancestor(of: find.text('UUID'), matching: find.byType(DetailRow)),
      );
      expect(row.copyText, _uuid);
    });

    testWidgets('reveals the key from its eye and hides it again', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const ProxyConnectionSection(name: _name)));
      await tester.pump();

      await tester.tap(find.byGlyph(AppGlyphs.eye));
      await tester.pump();

      expect(find.text(_uuid), findsOneWidget);
      expect(find.byGlyph(AppGlyphs.eyeOff), findsOneWidget);

      await tester.tap(find.byGlyph(AppGlyphs.eyeOff));
      await tester.pump();

      expect(find.text(_uuid), findsNothing);
      expect(find.text('••••••••'), findsOneWidget);
    });

    testWidgets('names where the route leaves and its protocol', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ProxyConnectionSection(
            name: _name,
            exit: RouteExit(name: _name, type: 'Vless', address: '1.2.3.4:443'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Exit'), findsOneWidget);
      expect(find.text(_name), findsOneWidget);
      expect(find.text('Protocol'), findsOneWidget);
      expect(find.text('Vless'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('falls back to the address the exit names without a mapping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ProxyConnectionSection(
            exit: RouteExit(name: _name, type: 'Vless', address: '1.2.3.4:443'),
          ),
          definition: null,
        ),
      );
      await tester.pump();

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('1.2.3.4'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('443'), findsOneWidget);
    });

    testWidgets('a direct exit names no endpoint', (tester) async {
      await tester.pumpWidget(
        _app(
          const ProxyConnectionSection(
            name: 'DIRECT',
            exit: RouteExit(name: 'DIRECT', type: 'Direct', address: ''),
          ),
          definition: null,
        ),
      );
      await tester.pump();

      expect(find.text('Exit'), findsOneWidget);
      expect(find.text('DIRECT'), findsOneWidget);
      expect(find.text('Server'), findsNothing);
      expect(find.text('Port'), findsNothing);
    });

    testWidgets('stays out of the way when it knows nothing', (tester) async {
      await tester.pumpWidget(
        _app(const ProxyConnectionSection(), definition: null),
      );
      await tester.pump();

      expect(find.byType(DetailRow), findsNothing);
      expect(find.text('Connection'), findsNothing);
    });

    testWidgets('holds the exit row while the Core answers', (tester) async {
      await tester.pumpWidget(
        _app(const ProxyConnectionSection(pending: true), definition: null),
      );
      await tester.pump();

      expect(find.text('Exit'), findsOneWidget);
      expect(find.byType(SkeletonText), findsOneWidget);
    });
  });

  group('the tunnel section', () {
    Widget tunnel({List<RouteHit> hits = const []}) {
      return TestApp(
        locale: const Locale('en'),
        overrides: [
          proxyDefinitionProvider.overrideWith((_, _) async => _definition),
          outboundIpProbeProvider.overrideWithBuild(
            (_, _) => RoutedProbeState<String, IpInfo>({
              routedOutbound: ProbeEntry(
                phase: ProbePhase.fresh,
                stamp: RouteStamp(
                  coreEpoch: 1,
                  routeVersion: 1,
                  hostEpoch: 1,
                  proxied: true,
                  hits: hits,
                ),
              ),
            }),
          ),
        ],
        homeBuilder: (child) => Scaffold(body: child),
        child: const RoutedConnectionSection(),
      );
    }

    testWidgets('reads the exit the outbound answer names', (tester) async {
      await tester.pumpWidget(
        tunnel(
          hits: const [
            RouteHit(host: 'www.google.com', exit: '"HK 01" Vless 1.2.3.4:443'),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Exit'), findsOneWidget);
      expect(find.text(_name), findsOneWidget);
      expect(find.text('Vless'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('UUID'), findsOneWidget);
    });

    testWidgets('keeps quiet until the answer names an exit', (tester) async {
      await tester.pumpWidget(tunnel());
      await tester.pump();

      expect(find.byType(DetailRow), findsNothing);
    });
  });
}
