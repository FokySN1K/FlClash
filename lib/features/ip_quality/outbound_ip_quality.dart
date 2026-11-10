import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'labels.dart';

/// The quality of the address a node leaves by, read from the lookup the
/// node's outbound row already made: no second request, and the answer stays
/// in the database as long as any other quality does.
class OutboundIpQualitySection extends ConsumerWidget {
  const OutboundIpQualitySection({super.key, required this.target});

  /// The node whose address to describe, as `/proxies` names it.
  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ip = ref.watch(
      outboundIpProbeProvider.select(
        (state) => state.entryOf(target).value?.ip,
      ),
    );
    if (ip == null) {
      return const SizedBox.shrink();
    }
    final quality = ref.watch(ipQualityProvider(ip)).value;
    if (quality == null) {
      return const SizedBox.shrink();
    }
    final appLocalizations = context.appLocalizations;
    final flags = [
      if (quality.isTor) appLocalizations.ipFlagTor,
      if (quality.isAbuser) appLocalizations.ipFlagAbuser,
      if (quality.isVpn) appLocalizations.ipFlagVpn,
      if (quality.isProxy) appLocalizations.ipFlagProxy,
    ];
    final organization = quality.organization;
    final asn = switch (quality.asn) {
      final asn? => 'AS$asn',
      null => null,
    };
    return generateSection(
      title: appLocalizations.ipQualityShort,
      items: [
        DetailRow(
          title: appLocalizations.ipQualityLevel,
          value: Text(
            quality.level.label(context),
            style: TextStyle(color: quality.level.color(context)),
          ),
        ),
        DetailRow(
          title: appLocalizations.ipType,
          value: Text(quality.type.label(context)),
        ),
        if (organization != null)
          DetailRow(
            title: appLocalizations.ipOrganization,
            copyText: organization,
            value: Text(organization),
          ),
        if (asn != null)
          DetailRow(
            title: appLocalizations.ipAsn,
            copyText: asn,
            value: Text(asn),
          ),
        if (flags.isNotEmpty)
          DetailRow(
            title: appLocalizations.ipFlags,
            value: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [for (final flag in flags) MetaChip(label: flag)],
            ),
          ),
      ],
    );
  }
}
