import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The progress of a release download as a row or a dialog shows it: the phase,
/// the percentage, and the bytes behind them.
class ReleaseDownloadProgress extends StatelessWidget {
  final ReleaseDownloadState state;

  const ReleaseDownloadProgress({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final localizations = context.appLocalizations;
    final label = state.phase == ReleaseDownloadPhase.verifying
        ? localizations.verifyingUpdate
        : localizations.downloadingUpdate;
    final received = state.received.traffic.show;
    final bytes = state.total > 0
        ? '$received / ${state.total.traffic.show}'
        : received;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: AppTextStyle.footnote.of(context)),
            ),
            Text(
              '${state.percent}%',
              style: AppTextStyle.footnote.of(context, emphasized: true),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          minHeight: 4,
          value: state.progress,
          backgroundColor: colorScheme.primary.opacity15,
        ),
        const SizedBox(height: 6),
        Text(
          bytes,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The alert a download runs behind: it closes itself once the archive is ready
/// or the transfer is cancelled, and stays to explain a failure.
class ReleaseDownloadDialog extends ConsumerStatefulWidget {
  const ReleaseDownloadDialog({super.key});

  @override
  ConsumerState<ReleaseDownloadDialog> createState() =>
      _ReleaseDownloadDialogState();
}

class _ReleaseDownloadDialogState extends ConsumerState<ReleaseDownloadDialog> {
  var _closing = false;

  @override
  void initState() {
    super.initState();
    // A download that settled before this dialog opened has no transition to
    // react to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _closeIfSettled());
  }

  void _closeIfSettled() {
    if (_closing || !mounted) {
      return;
    }
    if (!ref.read(releaseDownloadProvider).closesDialog) {
      return;
    }
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(releaseDownloadProvider, (_, next) {
      if (next.closesDialog) {
        _closeIfSettled();
      }
    });
    final state = ref.watch(releaseDownloadProvider);
    final localizations = context.appLocalizations;
    final error = state.error;
    return CommonDialog(
      title: switch (state.phase) {
        ReleaseDownloadPhase.verifying => localizations.verifyingUpdate,
        ReleaseDownloadPhase.ready => localizations.updateReady,
        ReleaseDownloadPhase.failed => localizations.downloadFailed,
        _ => localizations.downloadingUpdate,
      },
      actions: [
        if (state.phase == ReleaseDownloadPhase.downloading)
          TextButton(
            onPressed: () =>
                ref.read(releaseDownloadProvider.notifier).cancel(),
            child: Text(localizations.cancel),
          )
        else if (!state.isBusy)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(localizations.close),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReleaseDownloadProgress(state: state),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              compactError(error),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
