import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:path/path.dart' as p;

/// One archive of a release, with the size and digest its answer publishes.
typedef ReleaseAsset = ({String name, String url, int? size, String? sha256});

/// The release pipeline names every archive after the platform and ABI it
/// builds for, so the suffix picks the file the download table links to
/// without this build having to know the version it asks about.
String? releaseAssetSuffix() {
  // dart:ffi names the running ABI after its platform and architecture, so the
  // tail of that name tells which build of an archive fits this process.
  final abi = Abi.current().toString();
  final isArm64 = abi.endsWith('_arm64');
  if (system.isWindows) {
    return isArm64 ? '-windows-arm64-setup.exe' : '-windows-amd64-setup.exe';
  }
  if (system.isMacOS) {
    return isArm64 ? '-macos-arm64.dmg' : '-macos-amd64.dmg';
  }
  if (system.isLinux) {
    return isArm64 ? '-linux-arm64.AppImage' : '-linux-amd64.AppImage';
  }
  if (system.isAndroid) {
    // The pipeline ships one APK per ABI, and only the two the phones use.
    if (isArm64) return '-android-arm64-v8a.apk';
    if (abi.endsWith('_arm')) return '-android-armeabi-v7a.apk';
    if (abi.endsWith('_x64')) return '-android-x86_64.apk';
  }
  return null;
}

/// The archive of [release] that this build can install, if it published one:
/// a release that built only other platforms answers nothing.
ReleaseAsset? releaseAsset(Map<String, dynamic> release, {String? suffix}) {
  final assetSuffix = suffix ?? releaseAssetSuffix();
  if (assetSuffix == null) {
    return null;
  }
  final assets = release['assets'];
  if (assets is! List) {
    return null;
  }
  for (final asset in assets) {
    if (asset is! Map<String, dynamic>) {
      continue;
    }
    final name = asset['name'];
    final url = asset['browser_download_url'];
    if (name is String && url is String && name.endsWith(assetSuffix)) {
      final size = asset['size'];
      return (
        name: name,
        url: url,
        size: size is int ? size : null,
        sha256: _assetSha256(asset['digest']),
      );
    }
  }
  return null;
}

/// GitHub names the digest as `sha256:<hex>`; anything else leaves it unchecked.
String? _assetSha256(Object? digest) {
  const prefix = 'sha256:';
  if (digest is! String) {
    return null;
  }
  final value = digest.toLowerCase();
  if (!value.startsWith(prefix)) {
    return null;
  }
  final hash = value.substring(prefix.length);
  return _sha256Pattern.hasMatch(hash) ? hash : null;
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// The archives a release page links to, shaped like the `assets` of the API
/// answer so both sources feed [releaseAsset] the same way. The page is the
/// only place that still names them once the hourly API quota is spent.
List<Map<String, dynamic>> releaseAssetsFromPage(
  String html, {
  required String tag,
}) {
  final assets = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final match in _hrefPattern.allMatches(html)) {
    final uri = Uri.tryParse(match.group(1)!);
    if (uri == null) {
      continue;
    }
    final segments = uri.pathSegments;
    final download = segments.lastIndexOf('download');
    // An archive is linked as <owner>/<repo>/releases/download/<tag>/<name>;
    // the tag has to match, or a link to a neighbouring release on the page
    // would answer for this one.
    if (download < 2 || segments.length != download + 3) {
      continue;
    }
    if (segments[download - 1] != 'releases' || segments[download + 1] != tag) {
      continue;
    }
    final name = segments.last;
    if (!seen.add(name)) {
      continue;
    }
    assets.add({'name': name, 'browser_download_url': _assetUrl(uri)});
  }
  return assets;
}

final _hrefPattern = RegExp(r'href="([^"]+)"');

String _assetUrl(Uri uri) {
  final link = uri.replace(query: null, fragment: null);
  return link.hasScheme ? link.toString() : 'https://github.com$link';
}

const _releaseDownloadAttempts = 3;
const _latestUpdateVersion = 'latest';
final _unsafeUpdateVersionPattern = RegExp(r'[^0-9A-Za-z._-]');

Future<Directory> _updateDirectory(String? version) async {
  final root = Directory(p.join(await appPath.homeDirPath, 'updates'));
  final name = (version ?? _latestUpdateVersion).replaceAll(
    _unsafeUpdateVersionPattern,
    '_',
  );
  final directory = Directory(p.join(root.path, name));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<void> _pruneUpdates(Directory keep) async {
  try {
    await for (final entity in keep.parent.list()) {
      if (entity.path == keep.path) {
        continue;
      }
      await entity.delete(recursive: true);
    }
  } on FileSystemException catch (error) {
    commonPrint.log(
      'update cleanup failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  }
}

/// Streams [asset] to a `.part` and renames it once the bytes match.
Future<File> downloadReleaseAsset(
  ReleaseAsset asset, {
  String? version,
  void Function(int received, int total)? onDownloadProgress,
  void Function(int done, int total)? onVerifyProgress,
  CancelToken? cancelToken,
}) async {
  final directory = await _updateDirectory(version);
  final file = File(p.join(directory.path, asset.name));
  if (await _matchesRelease(file, asset, onVerifyProgress: onVerifyProgress)) {
    return file;
  }
  await _pruneUpdates(directory);
  final part = File('${file.path}.part');
  DioException? failure;
  for (var attempt = 0; attempt < _releaseDownloadAttempts; attempt++) {
    final startAt = await _lengthOf(part);
    // What the host says the whole archive is. The release page names its
    // archives without a size or a digest, so this length is what a finished
    // transfer is checked against.
    var expectedTotal = -1;
    try {
      final response = await request.downloadToFile(
        asset.url,
        part.path,
        startAt: startAt,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            expectedTotal = total;
          }
          onDownloadProgress?.call(received, total);
        },
      );
      // A server that ignores the Range answers 200, and the appended tail
      // would corrupt the archive.
      if (startAt > 0 && response.statusCode == HttpStatus.ok) {
        await part.delete();
        continue;
      }
      if (!await _matchesRelease(
        part,
        asset,
        expectedTotal: expectedTotal,
        onVerifyProgress: onVerifyProgress,
      )) {
        await part.delete();
        continue;
      }
      await part.rename(file.path);
      return file;
    } on DioException catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        rethrow;
      }
      // A part the host refuses to resume — a leftover longer than the
      // archive, a file that changed between attempts — would make every
      // later attempt send the same rejected range, so it starts over.
      if (error.response?.statusCode ==
          HttpStatus.requestedRangeNotSatisfiable) {
        await part.delete();
        continue;
      }
      failure = error;
    }
  }
  if (failure != null) {
    throw failure;
  }
  throw StateError('The archive of ${asset.name} did not match the release');
}

Future<String> fileSha256(
  File file, {
  void Function(int done, int total)? onProgress,
}) async {
  final total = await file.length();
  final collector = _DigestCollector();
  final output = sha256.startChunkedConversion(collector);
  var done = 0;
  await for (final chunk in file.openRead()) {
    output.add(chunk);
    done += chunk.length;
    onProgress?.call(done, total);
  }
  output.close();
  return collector.value.toString();
}

class _DigestCollector implements Sink<Digest> {
  late final Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// A file matches [asset] when it carries the published size and digest. A
/// release page publishes neither, so there [expectedTotal] — the length the
/// host reported while the body streamed — is what a finished transfer is
/// checked against, and a non-empty file with no length to compare is taken as
/// it arrived. Refusing that one would download the same archive on every
/// attempt and never install anything.
Future<bool> _matchesRelease(
  File file,
  ReleaseAsset asset, {
  int expectedTotal = -1,
  void Function(int done, int total)? onVerifyProgress,
}) async {
  if (!await file.exists()) {
    return false;
  }
  final length = await file.length();
  final size = asset.size;
  if (size != null && length != size) {
    return false;
  }
  final sha256 = asset.sha256;
  if (sha256 != null) {
    return await fileSha256(file, onProgress: onVerifyProgress) == sha256;
  }
  if (size != null) {
    return true;
  }
  if (length == 0) {
    return false;
  }
  return expectedTotal <= 0 || length == expectedTotal;
}

Future<int> _lengthOf(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return 0;
  }
}

/// Opens the downloaded archive and answers whether this process has to make
/// way: the Windows setup replaces the running executable, so the app quits as
/// soon as the installer is up, while the other platforms keep running.
Future<bool> launchReleaseAsset(File file) async {
  if (system.isWindows) {
    // The setup runs silent and starts the app again from [Run].
    if (!Windows().runas(file.path, '/SILENT /NORESTART /CLOSEAPPLICATIONS')) {
      throw StateError('Windows declined to run ${file.path}');
    }
    return true;
  }
  if (system.isMacOS) {
    await Process.start('open', [file.path]);
    return false;
  }
  if (system.isLinux) {
    if (file.path.endsWith('.AppImage')) {
      await Process.run('chmod', ['+x', file.path]);
    }
    await Process.run('xdg-open', [file.path]);
    return false;
  }
  if (system.isAndroid) {
    // The installer runs in its own task and the package replaces this one when
    // the user confirms, so nothing asks this process to step aside.
    if (!await (app?.installApk(file.path) ?? Future.value(false))) {
      throw StateError('Android declined to install ${file.path}');
    }
    return false;
  }
  return false;
}
