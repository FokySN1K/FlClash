import 'package:fl_clash/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release(List<String> names) => {
  'tag_name': 'v1.0.6',
  'assets': [
    for (final name in names)
      {'name': name, 'browser_download_url': 'https://example.com/$name'},
  ],
};

void main() {
  group('releaseAsset', () {
    test('takes the setup the suffix names, not the portable zip', () {
      final asset = releaseAsset(
        _release([
          'FlClash-1.0.6-windows-amd64.zip',
          'FlClash-1.0.6-windows-amd64-setup.exe',
        ]),
        suffix: '-windows-amd64-setup.exe',
      );

      expect(asset, (
        name: 'FlClash-1.0.6-windows-amd64-setup.exe',
        url: 'https://example.com/FlClash-1.0.6-windows-amd64-setup.exe',
      ));
    });

    test('answers nothing when the release built another platform', () {
      final asset = releaseAsset(
        _release(['FlClash-1.0.6-android-arm64-v8a.apk']),
        suffix: '-macos-arm64.dmg',
      );

      expect(asset, isNull);
    });

    test('answers nothing when the release lists no assets', () {
      expect(releaseAsset({'tag_name': 'v1.0.6'}, suffix: '.dmg'), isNull);
    });
  });

  group('releaseAssetsFromPage', () {
    // The release page lists every archive twice: its name links to the file
    // and the details row repeats the link. A neighbouring release and the
    // source archive sit on the same page and must not answer.
    const html = '''

<a href="/FokySN1K/FlClash/releases/download/v1.0.9/FlClash-1.0.9-android-arm64-v8a.apk" rel="nofollow" data-turbo="false" class="wb-break-all">
<a href="/FokySN1K/FlClash/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe" rel="nofollow" data-turbo="false" class="wb-break-all">
<a href="/FokySN1K/FlClash/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe" rel="nofollow">
<a href="/FokySN1K/FlClash/releases/download/v1.0.8/FlClash-1.0.8-windows-amd64-setup.exe" rel="nofollow">
<a href="/FokySN1K/FlClash/archive/refs/tags/v1.0.9.zip" rel="nofollow">
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
        'https://github.com/FokySN1K/FlClash/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe',
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
            'https://github.com/FokySN1K/FlClash/releases/download/v1.0.9/FlClash-1.0.9-windows-amd64-setup.exe',
      ));
    });
  });
}
