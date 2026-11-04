import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// What the app knows about one node: the whole of its name, which a card only
/// has room to cut short, and the picks that card's menu offers.
Future<void> showProxyInfoSheet(
  BuildContext context, {
  required Proxy proxy,
  required String groupName,
  required GroupType groupType,
  String? testUrl,
}) {
  Widget build(BuildContext _) => _ProxyInfoSheet(
    proxy: proxy,
    groupName: groupName,
    groupType: groupType,
    testUrl: testUrl,
  );
  if (isSheetPage(context)) {
    return Navigator.of(context).push(PagedSheetRoute(builder: build));
  }
  return showSheet<void>(context: context, builder: build);
}

class _ProxyInfoSheet extends ConsumerWidget {
  const _ProxyInfoSheet({
    required this.proxy,
    required this.groupName,
    required this.groupType,
    required this.testUrl,
  });

  final Proxy proxy;
  final String groupName;
  final GroupType groupType;
  final String? testUrl;

  void _select(WidgetRef ref) {
    selectGroupProxy(
      ref,
      groupName: groupName,
      groupType: groupType,
      proxyName: proxy.name,
    );
  }

  void _addToLocalProxies(WidgetRef ref) {
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    globalState.safeRun(() => proxiesAction.addToLocalProxies(proxy.name));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final inUse = ref.watch(
      selectedProxyNameProvider(groupName).select((name) => name == proxy.name),
    );
    final pinned =
        groupType.isComputedSelected &&
        ref.watch(
          proxyNameProvider(groupName).select((name) => name == proxy.name),
        );
    final isCustomProfile = ref.watch(
      currentProfileProvider.select(
        (profile) => profile?.type == ProfileType.custom,
      ),
    );
    final provider = proxy.providerName;
    return CommonScaffold(
      title: appLocalizations.basicInfo,
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          bottom: 20 + context.bottomInset,
          top: context.contentTopPadding,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
            child: DecorationListItem(
              title: EmojiText(
                proxy.name,
                style: AppTextStyle.callout.of(context, emphasized: true),
              ),
              trailing: GlyphIcon(
                AppGlyphs.copy,
                size: 18,
                color: context.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => _copy(context),
            ),
          ),
          generateSection(
            items: [
              DetailRow(
                title: appLocalizations.proxyType,
                value: Text(proxy.type),
              ),
              if (provider != null)
                DetailRow(
                  title: appLocalizations.proxyProvider,
                  copyText: provider,
                  value: Text(provider),
                ),
              DetailRow(
                title: appLocalizations.proxyGroup,
                copyText: groupName,
                value: EmojiText(groupName),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.network,
            items: [
              _DelayRow(proxy: proxy, groupName: groupName, testUrl: testUrl),
              OutboundIpRow(target: proxy.name),
            ],
          ),
          generateSection(
            title: appLocalizations.other,
            items: [
              if (groupType == GroupType.Selector)
                SelectedDecorationListItem(
                  title: Text(appLocalizations.select),
                  isSelected: inUse,
                  onSelected: () => _select(ref),
                  onPressed: () => _select(ref),
                )
              else if (groupType.isComputedSelected)
                SelectedDecorationListItem(
                  title: Text(appLocalizations.preferred),
                  isSelected: pinned,
                  onSelected: () => _select(ref),
                  onPressed: () => _select(ref),
                ),
              if (isAddableToLocalProxies(
                proxy,
                isCustomProfile: isCustomProfile,
              ))
                DecorationListItem(
                  title: Text(appLocalizations.addToLocalProxies),
                  trailing: const GlyphIcon(AppGlyphs.listAdd),
                  onPressed: () => _addToLocalProxies(ref),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: proxy.name));
    if (!context.mounted) {
      return;
    }
    context.showNotifier(context.appLocalizations.copySuccess);
  }
}

/// A node's delay, with a test that reads as one on a card.
class _DelayRow extends ConsumerWidget {
  const _DelayRow({
    required this.proxy,
    required this.groupName,
    required this.testUrl,
  });

  final Proxy proxy;
  final String groupName;
  final String? testUrl;

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
    return DetailRow(
      title: appLocalizations.delay,
      value: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          if (testing)
            const CommonCircleLoading(size: 14)
          else if (delay == null)
            Text(appLocalizations.noInfo)
          else
            Text(
              delay > 0
                  ? '$delay ms'
                  : delayFailureText(delay, appLocalizations),
              style: TextStyle(color: context.colorScheme.delayColor(delay)),
            ),
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
