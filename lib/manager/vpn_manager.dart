import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnManager extends ConsumerStatefulWidget {
  final Widget child;

  const VpnManager({super.key, required this.child});

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  /// The app lists reach the VpnService only when it establishes the tunnel,
  /// and a profile update publishes new rules before the Core takes the new
  /// config: the delay lets that push land before the tunnel is re-created.
  static const _reapplyDelay = Duration(seconds: 2);

  Timer? _reapplyTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      vpnOptionsProvider.select((state) => state.value?.effective),
      (prev, next) {
        final running = ref.read(runningVpnOptionsProvider)?.effective;
        if (next == null ||
            prev == next ||
            running == null ||
            running == next) {
          return;
        }
        if (_accessOnlyDiffers(running, next)) {
          _scheduleReapply();
        } else {
          _showRestartTip();
        }
      },
    );
  }

  @override
  void dispose() {
    _reapplyTimer?.cancel();
    super.dispose();
  }

  /// A change the service reads besides the app lists still asks for a
  /// restart through the tip, which applies everything at once.
  bool _accessOnlyDiffers(VpnOptions running, VpnOptions next) {
    return _withoutAccess(running) == _withoutAccess(next) &&
        (running.accessControlProps != next.accessControlProps ||
            running.excludePackages != next.excludePackages);
  }

  VpnOptions _withoutAccess(VpnOptions options) => options.copyWith(
    accessControlProps: const AccessControlProps(),
    excludePackages: const [],
  );

  void _scheduleReapply() {
    _reapplyTimer?.cancel();
    _reapplyTimer = Timer(_reapplyDelay, () {
      unawaited(ref.read(setupActionProvider.notifier).reapplyVpn());
    });
  }

  void _showRestartTip() {
    _reapplyTimer?.cancel();
    dialogs.showNotifier(
      currentAppLocalizations.vpnConfigChangeDetected,
      level: MessageLevel.warning,
      actionState: MessageActionState(
        actionText: currentAppLocalizations.restart,
        action: () async {
          await ref.read(setupActionProvider.notifier).restartVpn();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
