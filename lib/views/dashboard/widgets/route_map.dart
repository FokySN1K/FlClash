import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/features/ip_quality/labels.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_targets.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Where traffic leaves by for every outbound the rules name: one address per
/// target, each looked up through its own target, so the map agrees with the
/// rules rather than with whichever source a single lookup reached first.
class RouteMapSection extends ConsumerWidget {
  const RouteMapSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final targets =
        ref.watch(routeTargetsProvider).value ?? const <RouteTarget>[];
    if (targets.isEmpty) {
      return const SizedBox.shrink();
    }
    final probing = ref.watch(
      outboundIpProbeProvider.select(
        (state) => targets.any((target) => state.isLoading(target.name)),
      ),
    );
    return generateSection(
      title: appLocalizations.exitNodes,
      actions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: appLocalizations.ipQualityRetry,
          isLoading: probing,
          onPressed: () => ref.read(outboundIpProbeProvider.notifier).refresh([
            for (final target in targets) target.name,
          ]),
        ),
      ],
      items: [for (final target in targets) RouteTargetRow(target: target)],
    );
  }
}

/// One target under the rules, with the share of them that reach it, the
/// quality of the address it leaves by and that address itself.
class RouteTargetRow extends ConsumerWidget {
  const RouteTargetRow({super.key, required this.target});

  final RouteTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final rules = target.rules > 0
        ? appLocalizations.rulesCount(target.rules, target.rules.compact)
        : null;
    final meta = [
      if (target.isDefault) appLocalizations.defaultText,
      ?rules,
    ].join(' · ');
    final ip = ref.watch(
      outboundIpProbeProvider.select(
        (state) => state.entryOf(target.name).value?.ip,
      ),
    );
    final quality = ip == null ? null : ref.watch(ipQualityProvider(ip)).value;
    return DecorationListItem(
      title: Row(
        children: [
          Expanded(
            child: EmojiText(
              target.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          DefaultTextStyle.merge(
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: OutboundIpValue(target: target.name, showRefresh: false),
            ),
          ),
        ],
      ),
      subtitle: meta.isEmpty && quality == null
          ? null
          : _RouteTargetMeta(meta: meta, quality: quality),
    );
  }
}

/// The share of the rules and the quality of the address, which the row reads
/// from the lookup it already made.
class _RouteTargetMeta extends StatelessWidget {
  const _RouteTargetMeta({required this.meta, required this.quality});

  final String meta;
  final IpQuality? quality;

  @override
  Widget build(BuildContext context) {
    final quality = this.quality;
    if (quality == null) {
      return Text(meta);
    }
    final level = quality.level;
    final label = [
      quality.type.label(context),
      level.label(context),
    ].join(' · ');
    return Text.rich(
      TextSpan(
        children: [
          if (meta.isNotEmpty) TextSpan(text: '$meta · '),
          TextSpan(
            text: label,
            style: TextStyle(color: level.color(context)),
          ),
        ],
      ),
    );
  }
}
