import 'dart:io';
import 'dart:isolate';

import 'package:pake_cli/src/patch/android.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// `dart test` runs suites concurrently in one process, and
// `Directory.current` is a process-wide OS property — a relative path here
// would transiently resolve against whatever cwd another suite (e.g.
// runner_test.dart, which chdirs for its own tests) happens to have set.
// Resolving the fixtures directory via the package config instead sidesteps
// `Directory.current` entirely.
late final String _fixturesDir;

String _fixture(String name) =>
    File(p.join(_fixturesDir, name)).readAsStringSync();

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
  permissions: [PakePermission.camera, PakePermission.microphone],
);

void main() {
  setUpAll(() async {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:pake_cli/'),
    );
    _fixturesDir = p.normalize(
      p.join(libUri!.toFilePath(), '..', 'test', 'patch', 'fixtures'),
    );
  });

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

    test('opens cleartext traffic for an http:// url', () {
      // Android 9+ 默认禁明文。不开这个开关，`pakem build http://…` 构建
      // 成功、装上永远白屏，而报错还会指向「服务器返回了错误」。
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(url: 'http://192.168.1.10:8080'),
      );

      expect(out, contains('android:usesCleartextTraffic="true"'));
    });

    test('leaves cleartext closed for an https:// url', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config,
      );

      expect(out, isNot(contains('usesCleartextTraffic')));
    });

    test('drops the cleartext flag when the next build is https', () {
      // 固定 workspace 会被复用：上一个 app 是 http、这一个是 https 时，
      // 不删就把明文开关带进了一个不需要它的 app。
      final http = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(url: 'http://192.168.1.10:8080'),
      );
      final https = patchAndroidManifest(http, _config);

      expect(https, isNot(contains('usesCleartextTraffic')));
    });

    test('the cleartext flag is not duplicated on a second http patch', () {
      final config = _config.copyWith(url: 'http://192.168.1.10:8080');
      final once = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        config,
      );
      final twice = patchAndroidManifest(once, config);

      expect(twice, once);
      expect('usesCleartextTraffic'.allMatches(twice).length, 1);
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
