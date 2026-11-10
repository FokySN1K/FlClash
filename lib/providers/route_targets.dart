import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'core.dart';
import 'route_state.dart';

part 'generated/route_targets.g.dart';

/// The outbounds the applied rules send traffic to, in the order the rules
/// first reach them. Asked again when the Core moves its route counters: a
/// profile switch or a mode change rewrites the rules wholesale, and a Core
/// that cannot answer leaves the map empty.
@riverpod
Future<List<RouteTarget>> routeTargets(Ref ref) async {
  ref.watch(
    routeTrackerProvider.select(
      (state) => (state.coreEpoch, state.routeVersion),
    ),
  );
  final connected = ref.watch(
    coreStatusProvider.select((status) => status == CoreStatus.connected),
  );
  if (!connected) {
    return const [];
  }
  try {
    return await ref.read(coreHandlerProvider).routeTargets();
  } catch (error) {
    commonPrint.log(
      'route targets failed: $error',
      logLevel: coreFailureLogLevel(error),
    );
    return const [];
  }
}
