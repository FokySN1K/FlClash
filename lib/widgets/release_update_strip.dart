import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/release_download.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps an update download in sight without taking the page away: a three
/// pixel line while the archive is on its way, a short row with the install
/// action once it is ready, and nothing at all otherwise, so a user who never
/// downloads a release sees the page exactly as it was.
///
/// The strip stands at the top of the shell, above the page. On a phone that
/// band is the status bar area, so while the strip shows it takes the inset
/// over from the page instead of stacking a second one under itself.
class ReleaseUpdateStrip extends ConsumerStatefulWidget {
  final bool isMobile;
  final Widget child;

  const ReleaseUpdateStrip({
    super.key,
    required this.isMobile,
    required this.child,
  });

  @override
  ConsumerState<ReleaseUpdateStrip> createState() => _ReleaseUpdateStripState();
}

class _ReleaseUpdateStripState extends ConsumerState<ReleaseUpdateStrip> {
  static const _settleDuration = Duration(milliseconds: 150);

  var _dismissed = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(releaseDownloadProvider, (_, next) {
      // A new transfer brings the strip back after the ready row was closed.
      if (next.isBusy && _dismissed) {
        setState(() => _dismissed = false);
      }
    });
    final state = ref.watch(releaseDownloadProvider);
    final ready = state.phase == ReleaseDownloadPhase.ready && !_dismissed;
    final visible = state.isBusy || ready;
    final inset = widget.isMobile && visible
        ? MediaQuery.paddingOf(context).top
        : 0.0;
    return Column(
      children: [
        AnimatedSize(
          duration: _settleDuration,
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topCenter,
          child: state.isBusy
              ? _DownloadingStrip(
                  inset: inset,
                  state: state,
                  onTap: _showDownload,
                )
              : ready
              ? _ReadyStrip(
                  inset: inset,
                  onInstall: _install,
                  onDismiss: _dismiss,
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: widget.isMobile && visible,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  void _dismiss() {
    setState(() => _dismissed = true);
  }

  void _install() {
    unawaited(ref.read(commonActionProvider.notifier).installReadyRelease());
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

class _ReadyStrip extends StatelessWidget {
  static const _rowHeight = 40.0;
  static const _closeSize = 36.0;

  final double inset;
  final VoidCallback onInstall;
  final VoidCallback onDismiss;

  const _ReadyStrip({
    required this.inset,
    required this.onInstall,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final localizations = context.appLocalizations;
    return ColoredBox(
      color: colorScheme.primary.opacity15,
      child: Padding(
        padding: EdgeInsets.only(top: inset),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            children: [
              const SizedBox(width: 14),
              GlyphIcon(
                AppGlyphs.cloudDownload,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.updateReady,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.primary),
                ),
              ),
              TextButton(
                onPressed: onInstall,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(localizations.installNow),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: localizations.close,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: _closeSize,
                  height: _closeSize,
                ),
                icon: GlyphIcon(
                  AppGlyphs.close,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
