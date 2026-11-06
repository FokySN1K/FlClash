import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReleaseDownloadState', () {
    test('reads a known size as a percentage', () {
      const state = ReleaseDownloadState(
        phase: ReleaseDownloadPhase.downloading,
        received: 512,
        total: 1024,
      );

      expect(state.progress, 0.5);
      expect(state.percent, 50);
      expect(state.isBusy, isTrue);
      expect(state.closesDialog, isFalse);
    });

    test('stays indeterminate until the size is known', () {
      const state = ReleaseDownloadState(
        phase: ReleaseDownloadPhase.downloading,
      );

      expect(state.progress, isNull);
      expect(state.percent, 0);
    });

    test('closes its dialog once ready or cancelled, and not on a failure', () {
      expect(
        const ReleaseDownloadState(phase: ReleaseDownloadPhase.ready).progress,
        1,
      );
      expect(
        const ReleaseDownloadState(
          phase: ReleaseDownloadPhase.ready,
        ).closesDialog,
        isTrue,
      );
      expect(
        const ReleaseDownloadState(
          phase: ReleaseDownloadPhase.cancelled,
        ).closesDialog,
        isTrue,
      );
      expect(
        const ReleaseDownloadState(
          phase: ReleaseDownloadPhase.failed,
        ).closesDialog,
        isFalse,
      );
      expect(
        const ReleaseDownloadState(phase: ReleaseDownloadPhase.failed).isBusy,
        isFalse,
      );
    });
  });
}
