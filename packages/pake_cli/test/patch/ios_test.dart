import 'dart:io';
import 'dart:isolate';

import 'package:pake_cli/src/patch/ios.dart';
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
  permissions: [PakePermission.location],
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

  group('patchInfoPlist', () {
    test('rewrites the display name', () {
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(
        out,
        contains('''
	<key>CFBundleDisplayName</key>
	<string>Weibo</string>'''),
      );
    });

    test('leaves version keys on the xcode build variables', () {
      // 版本号经 `flutter build --build-name/--build-number` 传入，
      // 直接改 plist 反而会和 Flutter 工具链打架。
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(out, contains(r'$(FLUTTER_BUILD_NAME)'));
      expect(out, contains(r'$(FLUTTER_BUILD_NUMBER)'));
    });

    test('adds a usage-description key for each declared permission', () {
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(out, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
      expect(out, isNot(contains('NSCameraUsageDescription')));
    });

    test('is idempotent', () {
      final once = patchInfoPlist(_fixture('Info.plist.in'), _config);
      expect(patchInfoPlist(once, _config), once);
    });

    test('removes a usage description that is no longer declared', () {
      final withLocation = patchInfoPlist(_fixture('Info.plist.in'), _config);
      final without = patchInfoPlist(
        withLocation,
        _config.copyWith(permissions: []),
      );

      expect(without, isNot(contains('NSLocationWhenInUseUsageDescription')));
      expect(without, contains('<key>UILaunchStoryboardName</key>'));
    });

    test('escapes XML-significant characters in the display name', () {
      final out = patchInfoPlist(
        _fixture('Info.plist.in'),
        _config.copyWith(name: 'Tom & Jerry'),
      );

      expect(out, contains('<string>Tom &amp; Jerry</string>'));
    });

    test('inserts at the ROOT dict, not the first nested one', () {
      // Permissions must be at root level — iOS ignores them if nested.
      // Fixture has UIApplicationSceneManifest with nested dicts;
      // replaceFirst('</dict>') lands the key in that struct, causing device crash.
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      final keyAt = out.indexOf('NSLocationWhenInUseUsageDescription');
      final sceneManifestEnd = out.indexOf(
        '</dict>',
        out.indexOf('UISceneClassName'),
      );

      expect(
        keyAt,
        greaterThan(sceneManifestEnd),
        reason: 'usage description must sit outside the scene manifest',
      );
    });
  });

  group('patchPbxproj', () {
    test('rewrites every PRODUCT_BUNDLE_IDENTIFIER occurrence', () {
      const original = '''
				PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell.RunnerTests;
''';

      final out = patchPbxproj(original, _config);

      expect(out, contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo;'));
      expect(
        out,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo.RunnerTests;'),
        reason: 'the test target suffix must be preserved',
      );
    });
  });

  group('exportOptionsPlist', () {
    test('embeds team id, method and the profile mapping', () {
      final out = exportOptionsPlist(
        teamId: 'ABCDE12345',
        profileName: 'Pake Dev Profile',
        bundleId: 'com.pake.weibo',
      );

      expect(out, contains('<key>teamID</key>'));
      expect(out, contains('<string>ABCDE12345</string>'));
      expect(out, contains('<string>development</string>'));
      expect(out, contains('<key>com.pake.weibo</key>'));
      expect(out, contains('<string>Pake Dev Profile</string>'));
    });

    test('honours a non-default export method', () {
      final out = exportOptionsPlist(
        teamId: 'ABCDE12345',
        profileName: 'Pake AdHoc',
        bundleId: 'com.pake.weibo',
        method: 'ad-hoc',
      );

      expect(out, contains('<string>ad-hoc</string>'));
    });
  });
}
