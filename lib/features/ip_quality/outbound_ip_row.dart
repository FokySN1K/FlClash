import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/ip_quality/ip_quality_text.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The address an outbound leaves by, looked up through it, with a retry that
/// also covers a lookup that failed.
class OutboundIpRow extends ConsumerWidget {
  const OutboundIpRow({super.key, required this.target});

  /// A node name, `DIRECT`, or [routedOutbound] for whatever the rules pick.
  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(
      outboundIpProbeProvider.select(
        (state) => state.entryOf(target).value?.ip,
      ),
    );
    return DetailRow(
      title: context.appLocalizations.outboundIp,
      copyText: ip,
      value: OutboundIpValue(target: target),
    );
  }
}

/// The address alone, for a row that names its own target. Watching starts
/// with the widget and ends with it, so a sheet only looks up what it shows.
class OutboundIpValue extends ConsumerStatefulWidget {
  const OutboundIpValue({
    super.key,
    required this.target,
    this.showRefresh = true,
  });

  final String target;

  /// Whether the row that shows this value offers its own retry.
  final bool showRefresh;

  @override
  ConsumerState<OutboundIpValue> createState() => _OutboundIpValueState();
}

class _OutboundIpValueState extends ConsumerState<OutboundIpValue> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(widget.target);
  }

  @override
  void didUpdateWidget(OutboundIpValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) {
      return;
    }
    _probe
      ..unwatch(oldWidget.target)
      ..watch(widget.target);
  }

  @override
  void dispose() {
    _probe.unwatch(widget.target);
    super.dispose();
  }

  void _refresh() => _probe.refresh([widget.target]);

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(widget.target)),
    );
    final ip = entry.value?.ip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        if (ip != null)
          Flexible(child: IpQualityText(ip: ip))
        else if (entry.isLoading)
          const SkeletonText(width: 88)
        else
          Text(appLocalizations.noInfo),
        if (widget.showRefresh)
          IconButton(
            tooltip: appLocalizations.ipQualityRetry,
            onPressed: _refresh,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const GlyphIcon(AppGlyphs.refresh),
          ),
      ],
    );
  }
}
