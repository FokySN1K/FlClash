import 'dart:ffi';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:path/path.dart' as p;

/// One archive of a release, named and addressed the way GitHub serves it.
typedef ReleaseAsset = ({String name, String url});

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
      return (name: name, url: url);
    }
  }
  return null;
}

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

/// Streams [asset] into the folder the system can still read once this process
/// has stepped aside for the installer.
Future<File> downloadReleaseAsset(ReleaseAsset asset) async {
  final directory = Directory(await appPath.downloadDirPath);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final file = File(p.join(directory.path, asset.name));
  await request.downloadToFile(asset.url, file.path);
  return file;
}

/// Opens the downloaded archive and answers whether this process has to make
/// way: the Windows setup replaces the running executable, so the app quits as
/// soon as the wizard is up, while the other platforms keep running.
Future<bool> launchReleaseAsset(File file) async {
  if (system.isWindows) {
    if (!Windows().runas(file.path, '/NORESTART')) {
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
