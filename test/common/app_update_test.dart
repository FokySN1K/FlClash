import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _release(List<Map<String, dynamic>> assets) => {
  'tag_name': 'v1.0.6',
  'assets': [
    for (final asset in assets)
      {
        'browser_download_url': 'https://example.com/${asset['name']}',
        ...asset,
      },
  ],
};

void main() {
  group('releaseAsset', () {
    test('takes the setup the suffix names, not the portable zip', () {
      final asset = releaseAsset(
        _release([
          {'name': 'FlClash-1.0.6-windows-amd64.zip'},
          {'name': 'FlClash-1.0.6-windows-amd64-setup.exe'},
        ]),
        suffix: '-windows-amd64-setup.exe',
      );

      expect(asset, (
        name: 'FlClash-1.0.6-windows-amd64-setup.exe',
        url: 'https://example.com/FlClash-1.0.6-windows-amd64-setup.exe',
        size: null,
        sha256: null,
      ));
    });

    test('answers nothing when the release built another platform', () {
      final asset = releaseAsset(
        _release([
          {'name': 'FlClash-1.0.6-android-arm64-v8a.apk'},
        ]),
        suffix: '-macos-arm64.dmg',
      );

      expect(asset, isNull);
    });

    test('answers nothing when the release lists no assets', () {
      expect(releaseAsset({'tag_name': 'v1.0.6'}, suffix: '.dmg'), isNull);
    });

    test('keeps the size and the digest the release publishes', () {
      final asset = releaseAsset(
        _release([
          {
            'name': 'FlClash-1.0.6-windows-amd64-setup.exe',
            'size': 1048576,
            'digest': 'sha256:${'a' * 64}',
          },
        ]),
        suffix: '-windows-amd64-setup.exe',
      );

      expect(asset?.size, 1048576);
      expect(asset?.sha256, 'a' * 64);
    });

    test(
      'leaves the digest empty under another algorithm or a malformed one',
      () {
        for (final digest in [
          'sha512:${'a' * 128}',
          'md5:${'a' * 32}',
          'sha256:not-a-hash',
          'sha256:${'a' * 63}',
          'sha256:',
          '',
          42,
        ]) {
          final asset = releaseAsset(
            _release([
              {
                'name': 'FlClash-1.0.6-windows-amd64-setup.exe',
                'digest': digest,
              },
            ]),
            suffix: '-windows-amd64-setup.exe',
          );

          expect(asset?.sha256, isNull, reason: '$digest');
        }
      },
    );
  });

  group('releaseAssetsFromPage', () {
    // The release page lists every archive twice: its name links to the file
    // and the details row repeats the link. A neighbouring release and the
    // source archive sit on the same page and must not answer.
    const html = '''

<a href="/FokySN1K/SNKP/releases/download/v1.0.9/FlClash-1.0.9-android-arm64-v8a.apk" rel="nofollow" data-turbo="false" class="wb-break-all">
<a href="/FokySN1K/SNKP/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe" rel="nofollow" data-turbo="false" class="wb-break-all">
<a href="/FokySN1K/SNKP/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe" rel="nofollow">
<a href="/FokySN1K/SNKP/releases/download/v1.0.8/FlClash-1.0.8-windows-amd64-setup.exe" rel="nofollow">
<a href="/FokySN1K/SNKP/archive/refs/tags/v1.0.9.zip" rel="nofollow">
''';

    test('reads the archives the page links to, one entry per archive', () {
      final assets = releaseAssetsFromPage(html, tag: 'v1.0.9');

      expect(
        [for (final asset in assets) asset['name']],
        [
          'FlClash-1.0.9-android-arm64-v8a.apk',
          'FlClash-1.0.9-windows-amd64-setup.exe',
        ],
      );
      expect(
        assets.last['browser_download_url'],
        'https://github.com/FokySN1K/SNKP/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe',
      );
    });

    test('feeds the updater the way the API answer does', () {
      final release = {
        'tag_name': 'v1.0.9',
        'assets': releaseAssetsFromPage(html, tag: 'v1.0.9'),
      };

      expect(releaseAsset(release, suffix: '-windows-amd64-setup.exe'), (
        name: 'FlClash-1.0.9-windows-amd64-setup.exe',
        url:
            'https://github.com/FokySN1K/SNKP/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe',
        size: null,
        sha256: null,
      ));
    });
  });

  group('fileSha256', () {
    test(
      'hashes a file in chunks the way the release digest names it',
      () async {
        final directory = await Directory.systemTemp.createTemp('fl_clash_sha');
        addTearDown(() => directory.delete(recursive: true));
        final file = File(p.join(directory.path, 'archive.bin'));
        final bytes = List<int>.generate(200 * 1024, (index) => index % 251);
        await file.writeAsBytes(bytes);
        var reported = 0;

        final digest = await fileSha256(
          file,
          onProgress: (done, total) => reported = done,
        );

        expect(digest, sha256.convert(bytes).toString());
        expect(reported, bytes.length);
      },
    );
  });
}
