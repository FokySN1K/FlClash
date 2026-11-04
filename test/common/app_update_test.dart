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
}
