import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the VPN card stands for: whether the tunnel is up, the profile behind
/// it, the address its traffic leaves by and the takeover it shares a screen
/// with.
Future<void> showVpnInfoSheet(BuildContext context) {
  if (isSheetPage(context)) {
    return Navigator.of(
      context,
    ).push(PagedSheetRoute(builder: (_) => const _VpnInfoSheet()));
  }
  return showSheet<void>(
    context: context,
    builder: (_) => const _VpnInfoSheet(),
  );
}

class _VpnInfoSheet extends ConsumerWidget {
  const _VpnInfoSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final enabled = ref.watch(
      vpnSettingProvider.select((state) => state.enable),
    );
    final profile = ref.watch(currentProfileProvider);
    final tun = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.enable),
    );
    final systemProxy = ref.watch(
      networkSettingProvider.select((state) => state.systemProxy),
    );
    final mixedPort = ref.watch(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    return CommonScaffold(
      title: 'VPN',
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          bottom: 20 + context.bottomInset,
          top: context.contentTopPadding,
        ),
        children: [
          generateSection(
            items: [
              DetailRow(
                title: appLocalizations.status,
                value: Text(
                  enabled
                      ? appLocalizations.enabled
                      : appLocalizations.disabled,
                ),
              ),
              if (profile != null)
                DetailRow(
                  title: appLocalizations.profile,
                  copyText: profile.realLabel,
                  value: EmojiText(profile.realLabel),
                ),
            ],
          ),
          const RoutedConnectionSection(),
          generateSection(
            title: appLocalizations.network,
            items: [
              const OutboundIpRow(target: routedOutbound),
              DetailRow(
                title: appLocalizations.tun,
                value: Text(
                  tun ? appLocalizations.enabled : appLocalizations.disabled,
                ),
              ),
              DetailRow(
                title: appLocalizations.systemProxy,
                value: Text(
                  systemProxy
                      ? appLocalizations.portValue(mixedPort)
                      : appLocalizations.disabled,
                ),
              ),
              DetailRow(
                title: appLocalizations.mixedPort,
                copyText: '$mixedPort',
                value: Text('$mixedPort'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
