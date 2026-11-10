import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/proxy_details.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// How a node has been behaving: the verdict of its last check for the
/// group's target, the checks before it, and the transports it offers.
class ProxyHealthSection extends ConsumerWidget {
  const ProxyHealthSection({
    super.key,
    required this.proxy,
    required this.groupName,
    this.testUrl,
  });

  final Proxy proxy;
  final String groupName;
  final String? testUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final details = ref
        .watch(proxyDetailsProvider(proxyName: proxy.name, testUrl: testUrl))
        .value;
    final history = details?.history ?? const <DelaySample>[];
    final transports = details?.transports ?? const <String>[];
    final last = details?.last;
    final alive = last != null && last.delay > 0 && (details?.alive ?? false);
    return generateSection(
      title: appLocalizations.healthCheck,
      items: [
        DetailRow(
          title: appLocalizations.status,
          value: last == null
              ? Text(appLocalizations.noInfo)
              : Text(
                  alive
                      ? appLocalizations.serviceAvailable
                      : appLocalizations.serviceUnavailable,
                  style: TextStyle(
                    color: alive
                        ? context.colorScheme.success
                        : context.colorScheme.error,
                  ),
                ),
        ),
        _DelayHistoryRow(
          proxy: proxy,
          groupName: groupName,
          testUrl: testUrl,
          history: history,
        ),
        if (last != null)
          DetailRow(
            title: appLocalizations.lastUpdated,
            value: LastUpdateTimeText(
              lastUpdateDate: last.checkedAt,
              compact: true,
            ),
          ),
        if (transports.isNotEmpty)
          DetailRow(
            title: appLocalizations.transport,
            value: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                for (final transport in transports) MetaChip(label: transport),
              ],
            ),
          ),
      ],
    );
  }
}

/// The delay of the last check with the checks before it as a sparkline, and
/// the test that starts another one.
class _DelayHistoryRow extends ConsumerWidget {
  const _DelayHistoryRow({
    required this.proxy,
    required this.groupName,
    required this.testUrl,
    required this.history,
  });

  final Proxy proxy;
  final String groupName;
  final String? testUrl;
  final List<DelaySample> history;

  void _test(WidgetRef ref) {
    ref.read(proxiesActionProvider.notifier).proxyDelayTest(proxy, testUrl);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final delay = ref.watch(
      delayProvider(proxyName: proxy.name, testUrl: testUrl),
    );
    final testing =
        ref.watch(
          delayTestPhaseProvider(
            proxyName: proxy.name,
            testUrl: testUrl,
            groupName: groupName,
          ),
        ) !=
        null;
    final shown = delay ?? (history.isEmpty ? null : history.last.delay);
    return DetailRow(
      title: appLocalizations.delay,
      value: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          if (testing)
            const CommonCircleLoading(size: 14)
          else if (shown == null)
            Text(appLocalizations.noInfo)
          else
            Text(
              shown > 0
                  ? '$shown ms'
                  : delayFailureText(shown, appLocalizations),
              style: TextStyle(color: context.colorScheme.delayColor(shown)),
            ),
          if (history.length > 1) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 88,
              height: 24,
              child: LineChart(
                values: [for (final sample in history) sample.delay.toDouble()],
                revision: history.last.time,
                capacity: math.max(history.length, 10),
                minScale: 200,
                color:
                    context.colorScheme.delayColor(history.last.delay) ??
                    context.colorScheme.primary,
                baselineRatio: 0.9,
              ),
            ),
          ],
          IconButton(
            tooltip: appLocalizations.delayTest,
            onPressed: () => _test(ref),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const GlyphIcon(AppGlyphs.bolt),
          ),
        ],
      ),
    );
  }
}
