import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'core.dart';
import 'state.dart';

part 'generated/proxy_details.g.dart';

/// What the sheet shows about one node beyond its card. The history is made of
/// the checks [delayProvider] reports, so watching it reads the details again
/// once a result lands; a name the Core no longer holds reads as null.
@riverpod
Future<ProxyDetails?> proxyDetails(
  Ref ref, {
  required String proxyName,
  String? testUrl,
}) async {
  final currentTestUrl = ref.watch(realTestUrlProvider(testUrl));
  ref.watch(delayProvider(proxyName: proxyName, testUrl: testUrl));
  final connected = ref.watch(
    coreStatusProvider.select((status) => status == CoreStatus.connected),
  );
  if (!connected) {
    return null;
  }
  try {
    return await ref
        .read(coreHandlerProvider)
        .proxyDetails(
          ProxyDetailsParams(proxyName: proxyName, testUrl: currentTestUrl),
        );
  } catch (error) {
    commonPrint.log(
      'proxy details failed: $error',
      logLevel: coreFailureLogLevel(error),
    );
    return null;
  }
}
