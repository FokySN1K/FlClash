import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('profile_save_test');
    await useAppPaths(tempDir);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Profile.saveFile', () {
    // EditProfileView relies on this throwing rather than silently
    // succeeding, so a caller-level try/catch can surface the failure.
    test('rejects an invalid config without touching the saved file', () async {
      final profile = Profile.normal(label: 'p');
      final bytes = Uint8List.fromList(utf8.encode('bad: ['));

      await expectLater(
        profile.saveFile(bytes, validate: (_, _) async => 'invalid config'),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            'invalid config',
          ),
        ),
      );

      final savedFile = await profile.file;
      expect(await savedFile.length(), 0);
    });

    test('copies validated bytes and stamps the update time', () async {
      final profile = Profile.normal(label: 'p');
      final bytes = Uint8List.fromList(utf8.encode('proxies: []'));

      final saved = await profile.saveFile(bytes, validate: (_, _) async => '');

      expect(saved.lastUpdateDate, isNotNull);
      final savedFile = await profile.file;
      expect(await savedFile.readAsString(), 'proxies: []');
    });

    test('validates with the profile age key', () async {
      final profile = Profile.normal(
        label: 'p',
      ).copyWith(ageSecretKey: 'AGE-SECRET-KEY-1A');
      final bytes = Uint8List.fromList(utf8.encode('proxies: []'));
      String? ageSecretKey;

      await profile.saveFile(
        bytes,
        validate: (_, key) async {
          ageSecretKey = key;
          return '';
        },
      );

      expect(ageSecretKey, 'AGE-SECRET-KEY-1A');
    });
  });

  group('Profile.saveFile refresh interval', () {
    Uint8List config(String body) => Uint8List.fromList(utf8.encode(body));

    // The panels publish the interval inside the profile itself; the profile
    // list schedules its updates with it.
    test('takes the interval the file carries', () async {
      final profile = Profile.normal(label: 'p');

      final saved = await profile.saveFile(
        config('proxies: []\nprofile-update-interval: 21600'),
        validate: (_, _) async => '',
      );

      expect(saved.autoUpdateDuration, const Duration(hours: 6));
    });

    test('replaces the previous one while the profile keeps it', () async {
      final profile = Profile.normal(label: 'p');
      final first = await profile.saveFile(
        config('profile-update-interval: 3600'),
        validate: (_, _) async => '',
      );

      final second = await first.saveFile(
        config('profile-update-interval: 7200'),
        validate: (_, _) async => '',
      );

      expect(second.autoUpdateDuration, const Duration(hours: 2));
    });

    // A value the user typed in the editor outranks the one the panel sends.
    test('keeps the value the user picked', () async {
      final profile = Profile.normal(label: 'p');
      final saved = await profile.saveFile(
        config('profile-update-interval: 86400'),
        validate: (_, _) async => '',
      );
      final edited = saved.copyWith(
        autoUpdateDuration: const Duration(minutes: 30),
      );

      final updated = await edited.saveFile(
        config('profile-update-interval: 7200'),
        validate: (_, _) async => '',
      );

      expect(updated.autoUpdateDuration, const Duration(minutes: 30));
    });

    test('ignores a profile without the key', () async {
      final profile = Profile.normal(label: 'p');

      final saved = await profile.saveFile(
        config('proxies: []'),
        validate: (_, _) async => '',
      );

      expect(saved.autoUpdateDuration, defaultUpdateDuration);
    });

    // The file it replaces names no interval, so a value that is not the app
    // default can only come from the user.
    test('keeps the value set before the key appeared', () async {
      final profile = Profile.normal(label: 'p');
      final saved = await profile.saveFile(
        config('proxies: []'),
        validate: (_, _) async => '',
      );
      final edited = saved.copyWith(
        autoUpdateDuration: const Duration(days: 3),
      );

      final updated = await edited.saveFile(
        config('profile-update-interval: 21600'),
        validate: (_, _) async => '',
      );

      expect(updated.autoUpdateDuration, const Duration(days: 3));
    });

    test('takes a key the file starts naming over the default', () async {
      final profile = Profile.normal(label: 'p');
      final saved = await profile.saveFile(
        config('proxies: []'),
        validate: (_, _) async => '',
      );

      final updated = await saved.saveFile(
        config('profile-update-interval: 21600'),
        validate: (_, _) async => '',
      );

      expect(updated.autoUpdateDuration, const Duration(hours: 6));
    });
  });
}
