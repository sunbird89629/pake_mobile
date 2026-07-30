import 'dart:io';

import 'package:pake_cli/src/patch/android.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/patch/fixtures/$name').readAsStringSync();

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
  permissions: [PakePermission.camera, PakePermission.microphone],
);

void main() {
  group('patchBuildGradle', () {
    test('rewrites applicationId, namespace and version', () {
      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);

      expect(out, contains('applicationId = "com.pake.weibo"'));
      expect(out, contains('namespace = "com.pake.weibo"'));
      expect(out, contains('versionName = "2.1.0"'));
      expect(out, contains('versionCode = 42'));
      expect(out, isNot(contains('com.example.pake_shell')));
      expect(out, isNot(contains('flutter.versionCode')));
    });

    test('is idempotent — patching twice equals patching once', () {
      final once = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);
      expect(patchBuildGradle(once, _config), once);
    });

    test('leaves minSdk and targetSdk on the flutter defaults', () {
      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);

      expect(out, contains('minSdk = flutter.minSdkVersion'));
      expect(out, contains('targetSdk = flutter.targetSdkVersion'));
    });
  });

  group('patchAndroidManifest', () {
    test('rewrites the app label', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config,
      );

      expect(out, contains('android:label="Weibo"'));
      expect(out, isNot(contains('android:label="pake_shell"')));
    });

    test('adds a uses-permission line for each declared permission', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config,
      );

      expect(out, contains('android:name="android.permission.CAMERA"'));
      expect(out, contains('android:name="android.permission.RECORD_AUDIO"'));
      expect(out, isNot(contains('ACCESS_FINE_LOCATION')));
    });

    test('adds INTERNET, which is never optional for a webview shell', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(permissions: []),
      );

      expect(out, contains('android.permission.INTERNET'));
      expect('android.permission.INTERNET'.allMatches(out).length, 1);
    });

    test('does not duplicate permissions on a second patch', () {
      final once = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config,
      );
      final twice = patchAndroidManifest(once, _config);

      expect(twice, once);
      expect('android.permission.CAMERA'.allMatches(twice).length, 1);
    });

    test('removes a permission that is no longer declared', () {
      final withCamera = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config,
      );
      final withoutCamera = patchAndroidManifest(
        withCamera,
        _config.copyWith(permissions: []),
      );

      expect(withoutCamera, isNot(contains('android.permission.CAMERA')));
      expect(withoutCamera, contains('android.permission.INTERNET'));
    });

    test('escapes XML-significant characters in the app name', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(name: 'Tom & Jerry "Show"'),
      );

      expect(out, contains('android:label="Tom &amp; Jerry &quot;Show&quot;"'));
    });
  });
}
