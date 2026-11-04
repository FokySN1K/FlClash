import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/proxy_definition.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _secretMask = '••••••••';

/// What a node dials and the secret it proves itself with: `/proxies` carries
/// neither, so the rows come from the running config's mapping for the node
/// and from where the Core says a connection left.
class ProxyConnectionSection extends ConsumerWidget {
  const ProxyConnectionSection({
    super.key,
    this.name,
    this.exit,
    this.pending = false,
  });

  /// The node whose mapping to read. Null while the exit is not known yet.
  final String? name;

  /// The exit the Core named on the way through [name], when it has answered.
  final RouteExit? exit;

  /// Whether the Core is still on its way to naming [exit].
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final exit = this.exit;
    final name = this.name;
    final definition = name == null
        ? null
        : ref.watch(proxyDefinitionProvider(name)).value;
    final dial = _splitAddress(exit?.address ?? '');
    final server = _scalar(definition?['server']) ?? dial?.host;
    final port = _scalar(definition?['port']) ?? dial?.port;
    final sni =
        _scalar(definition?['sni']) ?? _scalar(definition?['servername']);
    final items = <Widget>[
      if (exit != null) ...[
        DetailRow(
          title: appLocalizations.outboundExit,
          copyText: exit.name,
          value: EmojiText(exit.name),
        ),
        DetailRow(
          title: appLocalizations.protocol,
          copyText: exit.type,
          value: Text(exit.type),
        ),
      ] else if (pending)
        _PendingRow(title: appLocalizations.outboundExit),
      if (server != null)
        DetailRow(
          title: appLocalizations.server,
          copyText: server,
          value: Text(server),
        ),
      if (port != null)
        DetailRow(
          title: appLocalizations.port,
          copyText: port,
          value: Text(port),
        ),
      if (sni != null && sni != server)
        DetailRow(title: 'SNI', copyText: sni, value: Text(sni)),
      for (final credential in _credentials(definition, appLocalizations))
        _SecretRow(title: credential.label, secret: credential.secret),
    ];
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return generateSection(title: appLocalizations.connection, items: items);
  }
}

/// The tunnel as a whole: the node the rules pick right now, read from the
/// answer the outbound lookup of the same sheet already has.
class RoutedConnectionSection extends ConsumerWidget {
  const RoutedConnectionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final exit = entry.stamp?.hits.exitInfo;
    return ProxyConnectionSection(
      name: exit?.name,
      exit: exit,
      pending: entry.isLoading,
    );
  }
}

/// A row whose value the Core has not answered yet.
class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DetailRow(title: title, value: const SkeletonText(width: 88));
  }
}

/// A secret held behind a mask until it is revealed: what the row copies is
/// always the secret itself, not the mask.
class _SecretRow extends StatefulWidget {
  const _SecretRow({required this.title, required this.secret});

  final String title;
  final String secret;

  @override
  State<_SecretRow> createState() => _SecretRowState();
}

class _SecretRowState extends State<_SecretRow> {
  var _revealed = false;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return DetailRow(
      title: widget.title,
      copyText: widget.secret,
      value: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Flexible(
            child: Text(
              _revealed ? widget.secret : _secretMask,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: _revealed
                ? appLocalizations.hidePassword
                : appLocalizations.showPassword,
            onPressed: () => setState(() => _revealed = !_revealed),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: GlyphIcon(_revealed ? AppGlyphs.eyeOff : AppGlyphs.eye),
          ),
        ],
      ),
    );
  }
}

/// The secret keys a node may be spelled with, a protocol that names the one
/// secret twice listing both.
const _secretKeys = [
  ['uuid'],
  ['password'],
  ['psk', 'pre-shared-key'],
  ['key'],
  ['private-key'],
  ['auth-str'],
  ['obfs-password'],
];

/// The secrets [definition] carries, labelled as the proxy form labels them.
List<({String label, String secret})> _credentials(
  Map<String, dynamic>? definition,
  AppLocalizations appLocalizations,
) {
  if (definition == null) {
    return const [];
  }
  final credentials = <({String label, String secret})>[];
  for (final keys in _secretKeys) {
    for (final key in keys) {
      final secret = _scalar(definition[key]);
      if (secret == null) {
        continue;
      }
      credentials.add((
        label: _secretLabel(key, appLocalizations),
        secret: secret,
      ));
      break;
    }
  }
  return credentials;
}

String _secretLabel(String key, AppLocalizations appLocalizations) =>
    switch (key) {
      'uuid' => 'UUID',
      'psk' || 'pre-shared-key' => appLocalizations.preSharedKey,
      'key' => appLocalizations.secretKey,
      'private-key' => appLocalizations.privateKey,
      'obfs-password' => appLocalizations.obfsPassword,
      _ => appLocalizations.password,
    };

/// A mapping's value as a row shows it: a list or a map is no value to show.
String? _scalar(Object? value) {
  if (value is Map || value is Iterable) {
    return null;
  }
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// The Core prints a node's address as `host:port`, bracketing an IPv6 host.
({String host, String? port})? _splitAddress(String address) {
  if (address.isEmpty) {
    return null;
  }
  if (address.startsWith('[')) {
    final close = address.indexOf(']');
    if (close > 0) {
      final rest = address.substring(close + 1);
      return (
        host: address.substring(1, close),
        port: rest.length > 1 ? rest.substring(1) : null,
      );
    }
  }
  final colon = address.lastIndexOf(':');
  if (colon < 0) {
    return (host: address, port: null);
  }
  final port = address.substring(colon + 1);
  return (host: address.substring(0, colon), port: port.isEmpty ? null : port);
}
