import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/release_download.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps an update download in sight without taking the page away: a three
/// pixel line while the archive is on its way and nothing at all otherwise, so
/// a user who never downloads a release sees the page exactly as it was. The
/// end of the transfer belongs to the install toast of commonActionProvider,
/// which is the only surface that offers the action.
///
/// The strip stands at the top of the shell, above the page. On a phone that
/// band is the status bar area, so while the strip shows it takes the inset
/// over from the page instead of stacking a second one under itself.
class ReleaseUpdateStrip extends ConsumerWidget {
  final bool isMobile;
  final Widget child;

  const ReleaseUpdateStrip({
    super.key,
    required this.isMobile,
    required this.child,
  });

  static const _settleDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(releaseDownloadProvider);
    final visible = state.isBusy;
    final inset = isMobile && visible ? MediaQuery.paddingOf(context).top : 0.0;
    return Column(
      children: [
        AnimatedSize(
          duration: _settleDuration,
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topCenter,
          child: visible
              ? _DownloadingStrip(
                  inset: inset,
                  state: state,
                  onTap: _showDownload,
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: isMobile && visible,
            child: child,
          ),
        ),
      ],
    );
  }

  Future<void> _showDownload() {
    return dialogs.showCommonDialog<void>(child: const ReleaseDownloadDialog());
  }
}

class _DownloadingStrip extends StatelessWidget {
  static const _lineHeight = 3.0;

  final double inset;
  final ReleaseDownloadState state;
  final Future<void> Function() onTap;

  const _DownloadingStrip({
    required this.inset,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = context.appLocalizations;
    final label = state.phase == ReleaseDownloadPhase.verifying
        ? localizations.verifyingUpdate
        : localizations.downloadingUpdate;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(onTap()),
      child: Tooltip(
        message: '$label ${state.percent}%',
        child: Padding(
          padding: EdgeInsets.only(top: inset),
          child: SizedBox(
            height: _lineHeight,
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: _lineHeight,
              backgroundColor: context.colorScheme.primary.opacity15,
            ),
          ),
        ),
      ),
    );
  }
}
