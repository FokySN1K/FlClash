import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/release_download.freezed.dart';

enum ReleaseDownloadPhase { downloading, verifying, ready, failed, cancelled }

/// What an update download reports to the dialog and to the rows that show it.
@freezed
abstract class ReleaseDownloadState with _$ReleaseDownloadState {
  const factory ReleaseDownloadState({
    ReleaseDownloadPhase? phase,
    @Default(0) int received,
    @Default(0) int total,
    Object? error,
  }) = _ReleaseDownloadState;
}

extension ReleaseDownloadStateExt on ReleaseDownloadState {
  bool get isBusy =>
      phase == ReleaseDownloadPhase.downloading ||
      phase == ReleaseDownloadPhase.verifying;

  bool get closesDialog =>
      phase == ReleaseDownloadPhase.ready ||
      phase == ReleaseDownloadPhase.cancelled;

  double? get progress {
    if (phase == ReleaseDownloadPhase.ready) {
      return 1;
    }
    if (total <= 0) {
      return null;
    }
    return (received / total).clamp(0.0, 1.0);
  }

  int get percent => ((progress ?? 0) * 100).round();
}
