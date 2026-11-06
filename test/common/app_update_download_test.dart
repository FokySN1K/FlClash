import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import '../helpers/app_paths.dart';

/// Stands in for the release host: it serves the archive over a real socket,
/// honours the Range a resume asks for unless told otherwise, and remembers what
/// every attempt sent.
class _ReleaseHost {
  _ReleaseHost._(this._server, this.bytes);

  final HttpServer _server;
  final List<int> bytes;

  /// Every request the download made, as the Range header it carried.
  final ranges = <String?>[];

  /// A host that ignores the Range header answers 200 with the whole archive.
  bool ignoresRange = false;

  /// Holds the next answer until the test completes it.
  Completer<void>? hold;

  /// Sends the body in two halves, which lets progress report between them.
  bool slow = false;

  static Future<_ReleaseHost> start(List<int> bytes) async {
    final host = _ReleaseHost._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      bytes,
    );
    host._server.listen(host._answer);
    return host;
  }

  String urlOf(String name) => 'http://127.0.0.1:${_server.port}/$name';

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    final holding = hold;
    hold = null;
    await holding?.future;
    final start = ignoresRange ? 0 : _startOf(range);
    final body = bytes.sublist(start);
    final response = request.response
      ..statusCode = start == 0 ? HttpStatus.ok : HttpStatus.partialContent
      ..headers.contentLength = body.length;
    if (!slow) {
      response.add(body);
      await response.close();
      return;
    }
    final half = body.length ~/ 2;
    response.add(body.sublist(0, half));
    await response.flush();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    response.add(body.sublist(half));
    await response.close();
  }
}

/// The offset a `bytes=<offset>-` range asks for, or 0 for no range at all.
int _startOf(String? range) {
  if (range == null) {
    return 0;
  }
  final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range);
  return match == null ? 0 : int.parse(match.group(1)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _ReleaseHost host;
  late List<int> bytes;
  late ProviderContainer container;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '1.0.0',
      buildNumber: '1',
    );
  });

  setUp(() async {
    // The test binding answers every request with a 400 of its own.
    final bindingOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = bindingOverrides);
    root = await Directory.systemTemp.createTemp('fl_clash_update');
    addTearDown(() => root.delete(recursive: true));
    await useAppPaths(root);
    container = ProviderContainer();
    globalState.container = container;
    bytes = List<int>.generate(64 * 1024, (index) => index % 251);
    host = await _ReleaseHost.start(bytes);
    addTearDown(host.close);
  });

  tearDown(() => container.dispose());

  ReleaseAsset assetFor({
    String name = 'FlClash-1.0.6-linux-amd64.AppImage',
    int? size,
    String? sha256,
  }) {
    return (
      name: name,
      url: host.urlOf(name),
      size: size ?? bytes.length,
      sha256: sha256 ?? _digestOf(bytes),
    );
  }

  Directory versionDirectory(String version) =>
      Directory(p.join(root.path, 'updates', version));

  Future<Directory> versionDirectoryOf(String version) async {
    final directory = versionDirectory(version);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  test(
    'keeps the finished archive under its name and drops the part',
    () async {
      var reported = 0;
      var reportedTotal = 0;

      final file = await downloadReleaseAsset(
        assetFor(),
        version: 'v1.0.6',
        onDownloadProgress: (received, total) {
          reported = received;
          reportedTotal = total;
        },
      );

      expect(p.dirname(file.path), versionDirectory('v1.0.6').path);
      expect(p.basename(file.path), 'FlClash-1.0.6-linux-amd64.AppImage');
      expect(await file.readAsBytes(), bytes);
      expect(await File('${file.path}.part').exists(), isFalse);
      expect(reported, bytes.length);
      expect(reportedTotal, bytes.length);
    },
  );

  test('takes the archive an earlier run already checked', () async {
    final directory = await versionDirectoryOf('v1.0.6');
    final file = File(
      p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage'),
    );
    await file.writeAsBytes(bytes);

    final downloaded = await downloadReleaseAsset(
      assetFor(),
      version: 'v1.0.6',
    );

    expect(downloaded.path, file.path);
    expect(host.ranges, isEmpty);
  });

  test('clears the archives of the versions before it', () async {
    final older = await versionDirectoryOf('v1.0.5');
    await File(
      p.join(older.path, 'FlClash-1.0.5-linux-amd64.AppImage'),
    ).writeAsBytes(bytes);

    await downloadReleaseAsset(assetFor(), version: 'v1.0.6');

    expect(await versionDirectory('v1.0.5').exists(), isFalse);
    expect(await versionDirectory('v1.0.6').exists(), isTrue);
  });

  test('resumes the part an earlier attempt left behind', () async {
    final directory = await versionDirectoryOf('v1.0.6');
    final part = File(
      p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage.part'),
    );
    await part.writeAsBytes(bytes.sublist(0, 8));

    final file = await downloadReleaseAsset(assetFor(), version: 'v1.0.6');

    expect(host.ranges, ['bytes=8-']);
    expect(await file.readAsBytes(), bytes);
    expect(await part.exists(), isFalse);
  });

  test('counts the progress on from the bytes the part holds', () async {
    final directory = await versionDirectoryOf('v1.0.6');
    await File(
      p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage.part'),
    ).writeAsBytes(bytes.sublist(0, 8));
    final reported = <(int, int)>[];

    await downloadReleaseAsset(
      assetFor(),
      version: 'v1.0.6',
      onDownloadProgress: (received, total) => reported.add((received, total)),
    );

    expect(reported.first.$1, greaterThanOrEqualTo(8));
    expect(reported.last.$1, bytes.length);
    expect(reported.last.$2, bytes.length);
  });

  test('starts the archive again when the host ignores the range', () async {
    final directory = await versionDirectoryOf('v1.0.6');
    final part = File(
      p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage.part'),
    );
    await part.writeAsBytes(List<int>.filled(8, 0));
    host.ignoresRange = true;

    final file = await downloadReleaseAsset(assetFor(), version: 'v1.0.6');

    expect(host.ranges.first, 'bytes=8-');
    expect(await file.readAsBytes(), bytes);
    expect(await part.exists(), isFalse);
  });

  test('refuses an archive that does not match the digest', () async {
    final otherDigest = _digestOf(List<int>.filled(bytes.length, 7));

    await expectLater(
      downloadReleaseAsset(
        assetFor(size: bytes.length, sha256: otherDigest),
        version: 'v1.0.6',
      ),
      throwsA(isA<StateError>()),
    );

    final directory = versionDirectory('v1.0.6');
    expect(
      await File(
        p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage'),
      ).exists(),
      isFalse,
    );
    expect(
      await File(
        p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage.part'),
      ).exists(),
      isFalse,
    );
    expect(host.ranges, hasLength(3));
  });

  test('stops on cancel and keeps the part for the next run', () async {
    final cancelToken = CancelToken();
    host.slow = true;

    await expectLater(
      downloadReleaseAsset(
        assetFor(),
        version: 'v1.0.6',
        cancelToken: cancelToken,
        onDownloadProgress: (received, total) {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel();
          }
        },
      ),
      throwsA(isA<DioException>()),
    );

    final directory = versionDirectory('v1.0.6');
    expect(
      await File(
        p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage.part'),
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(directory.path, 'FlClash-1.0.6-linux-amd64.AppImage'),
      ).exists(),
      isFalse,
    );
  });
}

String _digestOf(List<int> bytes) => sha256.convert(bytes).toString();
