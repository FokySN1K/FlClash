import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/proxy_details.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/ui/line_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

const _proxy = Proxy(name: 'Proxy', type: 'ss');

const _healthy = ProxyDetails(
  alive: true,
  history: [
    DelaySample(time: 1700000000000, delay: 41),
    DelaySample(time: 1700000060000, delay: 42),
  ],
  udp: true,
  tfo: true,
);

Widget _app(ProxyDetails? details) {
  return TestApp(
    locale: const Locale('en'),
    overrides: [
      proxyDetailsProvider.overrideWith((ref, arg) async => details),
      delayProvider.overrideWith((ref, arg) => null),
      delayTestPhaseProvider.overrideWith((ref, arg) => null),
    ],
    child: Scaffold(
      body: ListView(
        children: [const ProxyHealthSection(proxy: _proxy, groupName: 'Proxy')],
      ),
    ),
  );
}

void main() {
  testWidgets('reads the last check as a live node', (tester) async {
    await tester.pumpWidget(_app(_healthy));
    await tester.pump();

    expect(find.text('Health check'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('Last updated'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('UDP'), findsOneWidget);
    expect(find.text('TFO'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('reads a failed check as a dead node', (tester) async {
    await tester.pumpWidget(
      _app(
        const ProxyDetails(
          history: [DelaySample(time: 1700000000000, delay: 0)],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('says nothing it has not measured', (tester) async {
    await tester.pumpWidget(_app(const ProxyDetails()));
    await tester.pump();

    expect(find.text('Health check'), findsOneWidget);
    expect(find.text('No info'), findsNWidgets(2));
    expect(find.text('Last updated'), findsNothing);
    expect(find.text('Transport'), findsNothing);
  });
}
