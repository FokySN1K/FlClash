import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';

part 'generated/proxy_definition.g.dart';

/// The mapping the running config holds for a node: the server, the port and
/// the secret that `/proxies` leaves out. A group, or a Core that cannot read
/// its config, answers null.
@riverpod
Future<Map<String, dynamic>?> proxyDefinition(Ref ref, String name) async {
  try {
    return await ref.read(coreHandlerProvider).getProxyDefinition(name);
  } catch (error) {
    commonPrint.log(
      'proxy definition failed: $error',
      logLevel: coreFailureLogLevel(error),
    );
    return null;
  }
}
