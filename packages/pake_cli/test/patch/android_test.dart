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
    test('rewrites applicationId and version, but leaves namespace alone', () {
      // namespace 是编译期包名，AndroidManifest.xml 里的相对
      // `.MainActivity` 就是拿它解析的；模板的 Kotlin 源码包名固定是
      // com.example.pake_shell，改了 namespace 会让 .MainActivity 解析
      // 到一个不存在的类，装上就崩溃（ClassNotFoundException）。
      // applicationId 才是运行时包标识，二者独立是 Android 的标准用法。
      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);

      expect(out, contains('applicationId = "com.pake.weibo"'));
      expect(out, contains('namespace = "com.example.pake_shell"'));
      expect(out, contains('versionName = "2.1.0"'));
      expect(out, contains('versionCode = 42'));
      expect(out, isNot(contains('flutter.versionCode')));
    });

    // 系统认的是 versionCode 不是 versionName。它不跟着 version 走的话，
    // bump 完版本号发出去，两个包在系统眼里一模一样。
    test('derives versionCode from version when no buildNumber is pinned', () {
      const config = PakeConfig(
        name: 'Weibo',
        url: 'https://m.weibo.cn',
        bundleId: 'com.pake.weibo',
        version: '2.1.0',
      );

      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), config);

      expect(out, contains('versionCode = 20100'));
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

    test(
      'the patched namespace still matches the package MainActivity.kt is '
      'compiled into, so the manifest\'s relative ".MainActivity" resolves',
      () {
        // 只对比字符串会撒谎：真正的不变量是「namespace 解出来的类真的
        // 存在」。这条测试直接读真实模板里的 Kotlin 源码和真实的
        // build.gradle.kts / AndroidManifest.xml，用一个 bundleId 跟模板
        // 包名不同的 config 去 patch，然后验证 patch 后的 namespace 仍然
        // 等于 MainActivity.kt 里声明的包名——这正是当初漏掉、导致真机
        // ClassNotFoundException 崩溃的那个不变量。就算以后有人把
        // MainActivity.kt 挪了地方，这条测试读的是源码本身，不会说谎。
        final shellDir = p.normalize(
          p.join(_fixturesDir, '..', '..', '..', '..', 'pake_shell'),
        );
        final mainActivityKt = File(
          p.join(
            shellDir,
            'android',
            'app',
            'src',
            'main',
            'kotlin',
            'com',
            'example',
            'pake_shell',
            'MainActivity.kt',
          ),
        ).readAsStringSync();
        final packageMatch = RegExp(
          r'^package\s+([\w.]+)',
          multiLine: true,
        ).firstMatch(mainActivityKt);
        expect(
          packageMatch,
          isNotNull,
          reason: 'MainActivity.kt must declare a package',
        );
        final compiledPackage = packageMatch!.group(1)!;

        final gradleSrc = File(
          p.join(shellDir, 'android', 'app', 'build.gradle.kts'),
        ).readAsStringSync();

        final config = _config.copyWith(bundleId: 'com.example.myapp');
        expect(
          config.bundleId,
          isNot(compiledPackage),
          reason:
              'the test is meaningless unless bundleId diverges from '
              'the template package',
        );

        final out = patchBuildGradle(gradleSrc, config);

        expect(out, contains('applicationId = "${config.bundleId}"'));
        expect(
          out,
          contains('namespace = "$compiledPackage"'),
          reason:
              'AndroidManifest.xml uses the relative ".MainActivity", which '
              'Android resolves against `namespace` — if namespace stops '
              'matching the package MainActivity.kt was compiled into, the '
              'app installs but crashes on launch with '
              'ClassNotFoundException',
        );
      },
    );
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

    test('escapes a leading @ so aapt does not read it as a resource '
        'reference', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(name: '@Home'),
      );

      expect(out, contains(r'android:label="\@Home"'));
    });

    test('escapes a leading ? so aapt does not read it as a theme '
        'attribute reference', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(name: '?App'),
      );

      expect(out, contains(r'android:label="\?App"'));
    });
  });
}
