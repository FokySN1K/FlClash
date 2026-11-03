import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/ip_quality/ip_quality_text.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The address an outbound leaves by, looked up through it, with a retry that
/// also covers a lookup that failed.
class OutboundIpRow extends ConsumerStatefulWidget {
  const OutboundIpRow({super.key, required this.target});

  /// A node name, `DIRECT`, or [routedOutbound] for whatever the rules pick.
  final String target;

  @override
  ConsumerState<OutboundIpRow> createState() => _OutboundIpRowState();
}

class _OutboundIpRowState extends ConsumerState<OutboundIpRow> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(widget.target);
  }

  @override
  void didUpdateWidget(OutboundIpRow oldWidget) {
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
    return DetailRow(
      title: appLocalizations.outboundIp,
      copyText: ip,
      value: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          if (ip != null)
            Flexible(child: IpQualityText(ip: ip))
          else if (entry.isLoading)
            const SkeletonText(width: 88)
          else
            Text(appLocalizations.noInfo),
          IconButton(
            tooltip: appLocalizations.ipQualityRetry,
            onPressed: _refresh,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const GlyphIcon(AppGlyphs.refresh),
          ),
        ],
      ),
    );
  }
}
