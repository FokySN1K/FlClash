import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/proxy_details.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

const _details = ProxyDetails(
  alive: true,
  history: [
    DelaySample(time: 1700000000000, delay: 41),
    DelaySample(time: 1700000060000, delay: 42),
  ],
  udp: true,
  xudp: true,
  smux: true,
);

void main() {
  late _MockCore core;

  setUpAll(
    () => registerFallbackValue(
      const ProxyDetailsParams(proxyName: '', testUrl: ''),
    ),
  );

  setUp(() => core = _MockCore());

  ProviderContainer build({bool connected = true}) {
    final container = ProviderContainer(
      overrides: [
        realTestUrlProvider.overrideWith(
          (ref, testUrl) => testUrl ?? 'https://config.test',
        ),
        delayProvider.overrideWith((ref, arg) => null),
        coreStatusProvider.overrideWithBuild(
          (_, _) => connected ? CoreStatus.connected : CoreStatus.disconnected,
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('reads the checks the Core reports for the node', () async {
    when(() => core.proxyDetails(any())).thenAnswer((_) async => _details);

    final details = await build().read(
      proxyDetailsProvider(
        proxyName: 'Proxy',
        testUrl: 'https://group.test',
      ).future,
    );

    expect(details?.history.map((sample) => sample.delay), [41, 42]);
    expect(details?.last?.checkedAt.millisecondsSinceEpoch, 1700000060000);
    expect(details?.transports, ['UDP', 'XUDP', 'SMUX']);
    verify(
      () => core.proxyDetails(
        const ProxyDetailsParams(
          proxyName: 'Proxy',
          testUrl: 'https://group.test',
        ),
      ),
    ).called(1);
  });

  test('asks about the node against the target the profile tests', () async {
    when(() => core.proxyDetails(any())).thenAnswer((_) async => _details);

    await build().read(proxyDetailsProvider(proxyName: 'Proxy').future);

    verify(
      () => core.proxyDetails(
        const ProxyDetailsParams(
          proxyName: 'Proxy',
          testUrl: 'https://config.test',
        ),
      ),
    ).called(1);
  });

  test('reads as null when the Core cannot answer', () async {
    when(() => core.proxyDetails(any())).thenThrow(Exception('gone'));

    expect(
      await build().read(proxyDetailsProvider(proxyName: 'Proxy').future),
      isNull,
    );
  });

  test('does not ask a Core that is not connected', () async {
    when(() => core.proxyDetails(any())).thenAnswer((_) async => _details);

    expect(
      await build(
        connected: false,
      ).read(proxyDetailsProvider(proxyName: 'Proxy').future),
      isNull,
    );
    verifyNever(() => core.proxyDetails(any()));
  });
}
