import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/materialize.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void _write(String path, String content) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

void main() {
  late Directory tmp;
  late String templateDir;
  late Workspace ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_mat');
    templateDir = '${tmp.path}/template';
    ws = Workspace(root: '${tmp.path}/pake')..ensureDirs();

    _write('$templateDir/lib/main.dart', 'void main() {}');
    _write(
      '$templateDir/android/app/build.gradle.kts',
      'android { applicationId = "com.example.pake_shell" }',
    );
    _write(
      '$templateDir/android/app/src/main/AndroidManifest.xml',
      '<manifest><application android:label="pake_shell"/></manifest>',
    );
    _write('$templateDir/ios/Runner/Info.plist', '''
<plist><dict>
	<key>CFBundleDisplayName</key>
	<string>Pake Shell</string>
</dict></plist>''');
    _write(
      '$templateDir/ios/Runner.xcodeproj/project.pbxproj',
      'PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell;',
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('syncTemplate', () {
    test('copies template files into the project dir', () {
      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(File('${ws.projectDir}/lib/main.dart').existsSync(), isTrue);
    });

    test('never touches incremental cache directories', () {
      // 模拟上一次构建留下的缓存。
      _write('${ws.projectDir}/.dart_tool/version', 'cached');
      _write('${ws.projectDir}/build/app/stale.apk', 'cached');
      _write('${ws.projectDir}/android/.gradle/lock', 'cached');
      _write('${ws.projectDir}/ios/Pods/Manifest.lock', 'cached');
      // 模板里也放一份同名文件，确认它不会被复制过来。
      _write('$templateDir/.dart_tool/version', 'from-template');

      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(
        File('${ws.projectDir}/.dart_tool/version').readAsStringSync(),
        'cached',
        reason: 'losing this means every build is a cold build',
      );
      expect(File('${ws.projectDir}/build/app/stale.apk').existsSync(), isTrue);
      expect(
        File('${ws.projectDir}/android/.gradle/lock').existsSync(),
        isTrue,
      );
      expect(
        File('${ws.projectDir}/ios/Pods/Manifest.lock').existsSync(),
        isTrue,
      );
    });

    test('overwrites a template file that changed', () {
      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);
      _write('$templateDir/lib/main.dart', 'void main() { print(1); }');

      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(
        File('${ws.projectDir}/lib/main.dart').readAsStringSync(),
        contains('print(1)'),
      );
    });
  });

  group('materializeConfig', () {
    const config = PakeConfig(
      name: 'Weibo',
      url: 'https://m.weibo.cn',
      bundleId: 'com.pake.weibo',
      version: '2.1.0',
      buildNumber: 42,
    );

    setUp(
      () => syncTemplate(templateDir: templateDir, projectDir: ws.projectDir),
    );

    test('writes assets/pake.json that the shell can read back', () {
      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      final raw = File('${ws.projectDir}/assets/pake.json').readAsStringSync();
      final restored = PakeConfig.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );

      expect(restored.url, 'https://m.weibo.cn');
      expect(restored.name, 'Weibo');
    });

    test('patches gradle, manifest, plist and pbxproj', () {
      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      expect(
        File(
          '${ws.projectDir}/android/app/build.gradle.kts',
        ).readAsStringSync(),
        contains('com.pake.weibo'),
      );
      expect(
        File(
          '${ws.projectDir}/android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync(),
        contains('android:label="Weibo"'),
      );
      expect(
        File('${ws.projectDir}/ios/Runner/Info.plist').readAsStringSync(),
        contains('<string>Weibo</string>'),
      );
      expect(
        File(
          '${ws.projectDir}/ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync(),
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo;'),
      );
    });

    test('writes each inject script wrapped in try/catch', () {
      _write('${tmp.path}/hide-ads.js', 'document.body.remove();');

      materializeConfig(
        config: config.copyWith(injectScripts: ['${tmp.path}/hide-ads.js']),
        workspace: ws,
        cwd: tmp.path,
      );

      final out = File(
        '${ws.projectDir}/assets/scripts/hide-ads.js',
      ).readAsStringSync();
      expect(out, contains('try {'));
      expect(out, contains('document.body.remove();'));

      final manifest =
          jsonDecode(
                File(
                  '${ws.projectDir}/assets/scripts/index.json',
                ).readAsStringSync(),
              )
              as List<Object?>;
      expect(manifest.length, 1);
      expect((manifest.first! as Map)['id'], 'hide-ads');
    });

    test('drops scripts left over from a previous build', () {
      _write('${ws.projectDir}/assets/scripts/old.js', 'stale');
      _write('${ws.projectDir}/assets/scripts/index.json', '[{"id":"old"}]');

      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      expect(
        File('${ws.projectDir}/assets/scripts/old.js').existsSync(),
        isFalse,
      );
    });
  });
}
