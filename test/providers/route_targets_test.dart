import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/route_targets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

const _targets = [
  RouteTarget(name: 'DIRECT', rules: 2),
  RouteTarget(name: 'Автовыбор', rules: 5, isDefault: true),
];

void main() {
  late _MockCore core;

  setUp(() => core = _MockCore());

  ProviderContainer build({bool connected = true}) {
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => const RouteState(
            coreEpoch: 1,
            routeVersion: 1,
            synced: true,
            live: true,
          ),
        ),
        coreStatusProvider.overrideWithBuild(
          (_, _) => connected ? CoreStatus.connected : CoreStatus.disconnected,
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(routeTargetsProvider, (_, _) {});
    return container;
  }

  test('reads the Core answer into a target', () {
    final target = RouteTarget.fromJson(const {
      'name': 'DIRECT',
      'rules': 3,
      'default': true,
    });

    expect(target.name, 'DIRECT');
    expect(target.rules, 3);
    expect(target.isDefault, isTrue);
  });

  test('lists the targets in the order the rules reach them', () async {
    when(() => core.routeTargets()).thenAnswer((_) async => _targets);

    final targets = await build().read(routeTargetsProvider.future);

    expect(targets.map((target) => target.name), ['DIRECT', 'Автовыбор']);
    expect(targets.last.rules, 5);
    expect(targets.last.isDefault, isTrue);
  });

  test('leaves the map empty when the Core cannot answer', () async {
    when(() => core.routeTargets()).thenThrow(Exception('gone'));

    expect(await build().read(routeTargetsProvider.future), isEmpty);
  });

  test('does not ask a Core that is not connected', () async {
    when(() => core.routeTargets()).thenAnswer((_) async => _targets);

    expect(
      await build(connected: false).read(routeTargetsProvider.future),
      isEmpty,
    );
    verifyNever(() => core.routeTargets());
  });

  test('asks again when the Core moves its route counters', () async {
    when(() => core.routeTargets()).thenAnswer((_) async => _targets);
    final container = build();
    await container.read(routeTargetsProvider.future);

    container
        .read(routeTrackerProvider.notifier)
        .applySnapshot(const RouteSnapshot(coreEpoch: 1, routeVersion: 2));
    await container.read(routeTargetsProvider.future);

    verify(() => core.routeTargets()).called(2);
  });
}
