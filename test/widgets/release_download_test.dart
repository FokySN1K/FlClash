import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

class _TestReleaseDownload extends ReleaseDownload {
  _TestReleaseDownload(this._initial);

  final ReleaseDownloadState _initial;
  var cancelCalls = 0;

  @override
  ReleaseDownloadState build() => _initial;

  @override
  void cancel() => cancelCalls++;

  void emit(ReleaseDownloadState next) => state = next;
}

Widget _app(_TestReleaseDownload download, Widget child) {
  return TestApp(
    wrapInProviderScope: true,
    locale: const Locale('en'),
    overrides: [releaseDownloadProvider.overrideWith(() => download)],
    child: Scaffold(body: Center(child: child)),
  );
}

/// The alert opens over a page, so closing it leaves a route to fall back to.
Widget _dialogApp(_TestReleaseDownload download) {
  return _app(
    download,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showFloatingDialog<void>(
          context: context,
          dismissible: false,
          child: const ReleaseDownloadDialog(),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  // The bar sweeps while the size is unknown, so the route is stepped by hand
  // rather than settled.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The alert leaves on its own motion, which outlasts a single frame budget.
Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('reads the bytes and the percentage off the state', (
    tester,
  ) async {
    const state = ReleaseDownloadState(
      phase: ReleaseDownloadPhase.downloading,
      received: 512,
      total: 1024,
    );

    await tester.pumpWidget(
      _app(
        _TestReleaseDownload(state),
        const ReleaseDownloadProgress(state: state),
      ),
    );

    expect(find.text('Downloading the update'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('512B / 1KB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
  });

  testWidgets('leaves the bar indeterminate until the size is known', (
    tester,
  ) async {
    const state = ReleaseDownloadState(
      phase: ReleaseDownloadPhase.downloading,
      received: 512,
    );

    await tester.pumpWidget(
      _app(
        _TestReleaseDownload(state),
        const ReleaseDownloadProgress(state: state),
      ),
    );

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('512B'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
  });

  testWidgets('reads the verification as its own phase', (tester) async {
    const state = ReleaseDownloadState(
      phase: ReleaseDownloadPhase.verifying,
      received: 1024,
      total: 1024,
    );

    await tester.pumpWidget(
      _app(
        _TestReleaseDownload(state),
        const ReleaseDownloadProgress(state: state),
      ),
    );

    expect(find.text('Verifying the download'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('cancels the transfer from the dialog', (tester) async {
    final download = _TestReleaseDownload(
      const ReleaseDownloadState(
        phase: ReleaseDownloadPhase.downloading,
        total: 1024,
      ),
    );

    await tester.pumpWidget(_dialogApp(download));
    await _openDialog(tester);
    await tester.tap(find.text('Cancel'));

    expect(download.cancelCalls, 1);
    expect(find.byType(ReleaseDownloadDialog), findsOneWidget);
  });

  testWidgets('keeps a failure until the reader closes it', (tester) async {
    final download = _TestReleaseDownload(
      const ReleaseDownloadState(
        phase: ReleaseDownloadPhase.failed,
        error: MessageException('The archive did not match'),
      ),
    );

    await tester.pumpWidget(_dialogApp(download));
    await _openDialog(tester);

    expect(find.text('Download failed'), findsOneWidget);
    expect(find.text('The archive did not match'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('Close'));
    await _pumpRoute(tester);

    expect(find.byType(ReleaseDownloadDialog), findsNothing);
  });

  testWidgets('closes itself once the archive is ready', (tester) async {
    final download = _TestReleaseDownload(
      const ReleaseDownloadState(
        phase: ReleaseDownloadPhase.downloading,
        received: 512,
        total: 1024,
      ),
    );

    await tester.pumpWidget(_dialogApp(download));
    await _openDialog(tester);

    download.emit(
      const ReleaseDownloadState(phase: ReleaseDownloadPhase.ready),
    );
    await _pumpRoute(tester);

    expect(find.byType(ReleaseDownloadDialog), findsNothing);
  });

  testWidgets('closes itself once the transfer is cancelled', (tester) async {
    final download = _TestReleaseDownload(
      const ReleaseDownloadState(phase: ReleaseDownloadPhase.downloading),
    );

    await tester.pumpWidget(_dialogApp(download));
    await _openDialog(tester);

    download.emit(
      const ReleaseDownloadState(phase: ReleaseDownloadPhase.cancelled),
    );
    await _pumpRoute(tester);

    expect(find.byType(ReleaseDownloadDialog), findsNothing);
  });
}
