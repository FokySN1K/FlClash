import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/release_update_strip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// Pins the state the transfer notifier would settle on.
class _FixedDownload extends ReleaseDownload {
  _FixedDownload(this._initial);

  final ReleaseDownloadState _initial;

  @override
  ReleaseDownloadState build() => _initial;
}

Future<void> _pumpStrip(
  WidgetTester tester,
  ReleaseDownloadState state, {
  bool isMobile = false,
}) async {
  await tester.pumpWidget(
    TestApp(
      overrides: [
        releaseDownloadProvider.overrideWith(() => _FixedDownload(state)),
      ],
      child: Scaffold(
        body: ReleaseUpdateStrip(
          isMobile: isMobile,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keeps the page untouched while nothing downloads', (
    tester,
  ) async {
    await _pumpStrip(tester, const ReleaseDownloadState());
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(currentAppLocalizations.updateReady), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('shows a three pixel line while the archive downloads', (
    tester,
  ) async {
    await _pumpStrip(
      tester,
      const ReleaseDownloadState(
        phase: ReleaseDownloadPhase.downloading,
        received: 50,
        total: 100,
      ),
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.5);
    expect(tester.getSize(find.byType(LinearProgressIndicator)).height, 3);
  });

  testWidgets('verifying keeps the line and its label', (tester) async {
    await _pumpStrip(
      tester,
      const ReleaseDownloadState(
        phase: ReleaseDownloadPhase.verifying,
        received: 90,
        total: 100,
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('leaves the ready row to the install toast', (tester) async {
    await _pumpStrip(
      tester,
      const ReleaseDownloadState(phase: ReleaseDownloadPhase.ready),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(currentAppLocalizations.updateReady), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a failed transfer leaves no strip behind', (tester) async {
    await _pumpStrip(
      tester,
      const ReleaseDownloadState(phase: ReleaseDownloadPhase.failed),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(currentAppLocalizations.updateReady), findsNothing);
  });
}
