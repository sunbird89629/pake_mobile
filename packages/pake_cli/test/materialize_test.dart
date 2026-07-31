import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pake_cli/src/materialize.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;
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
    _write('$templateDir/pubspec.yaml', '''
name: pake_shell
dependencies:
  pake_config:
    path: ../pake_config
''');
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

    test('rewrites pubspec.yaml\'s pake_config path dependency to an absolute '
        'path, since the workspace is not a sibling of pake_config', () {
      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      final synced = File('${ws.projectDir}/pubspec.yaml').readAsStringSync();
      expect(synced, isNot(contains('../pake_config')));
      expect(
        synced,
        contains(
          'path: ${p.normalize(p.join(templateDir, '..', 'pake_config'))}',
        ),
      );
    });

    test(
      'does not crash on a re-sync of a binary file that is not valid utf-8',
      () {
        // 真实模板里混着 PNG 之类的二进制文件。第一次同步走 copySync，
        // 第二次同步（固定 workspace 复用时必然发生）会命中「内容相同就
        // 别写」的比较分支——这条分支曾经用 readAsStringSync 解码比较，
        // 在非 UTF-8 字节上直接抛异常。
        final pngBytes = [0x89, 0x50, 0x4e, 0x47, 0xff, 0xd8, 0x00, 0xc0];
        File('$templateDir/ios/Runner/Assets.xcassets/icon.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(pngBytes);

        syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);
        // Re-sync with identical content — must not throw.
        syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

        expect(
          File(
            '${ws.projectDir}/ios/Runner/Assets.xcassets/icon.png',
          ).readAsBytesSync(),
          pngBytes,
        );
      },
    );
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

    test('does not rewrite assets/pake.json when the config is unchanged', () {
      materializeConfig(config: config, workspace: ws, cwd: tmp.path);
      final file = File('${ws.projectDir}/assets/pake.json');
      final stamp = DateTime(2000);
      file.setLastModifiedSync(stamp);

      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      expect(
        file.lastModifiedSync(),
        stamp,
        reason:
            'an unnecessary mtime bump on an unchanged config invalidates '
            "Gradle's up-to-date checks",
      );
    });

    test(
      'throws with the missing path when a template file did not survive sync',
      () {
        File('${ws.projectDir}/android/app/build.gradle.kts').deleteSync();

        expect(
          () => materializeConfig(config: config, workspace: ws, cwd: tmp.path),
          throwsA(
            isA<PakeException>()
                .having((e) => e.exitCode, 'exitCode', ExitCodes.build)
                .having(
                  (e) => e.message,
                  'message',
                  contains('build.gradle.kts'),
                ),
          ),
        );
      },
    );

    test('throws even for an android-only build when the template is missing '
        'its ios subtree', () {
      // pake_shell 是单一 `flutter create --platforms=android,ios` 产物，
      // android/ios 两棵子树本该总是同时存在——`--platform` 只决定后面
      // 跑哪个 `flutter build`，不代表 workspace 里可以缺一棵子树。
      // 模板缺角说明模板安装坏了，materializeConfig 不区分请求的平台，
      // 该炸就炸，不能因为这次只打 android 就悄悄放过。
      Directory('${ws.projectDir}/ios').deleteSync(recursive: true);

      expect(
        () => materializeConfig(config: config, workspace: ws, cwd: tmp.path),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.build,
          ),
        ),
      );
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

    test(
      'does not rewrite icon files when materialized again with the same icon',
      () {
        final iconPath = '${tmp.path}/icon.png';
        File(
          iconPath,
        ).writeAsBytesSync(img.encodePng(img.Image(width: 512, height: 512)));
        final withIcon = config.copyWith(iconPath: iconPath);

        materializeConfig(config: withIcon, workspace: ws, cwd: tmp.path);

        // 内容相等的断言在新旧实现下都会通过——真正证明「没有重写」的
        // 只能是 mtime 或写入次数，跟 pake.json 的幂等性测试同一个道理。
        final androidIcon = File(
          '${ws.projectDir}/android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        );
        final iosIcon = File(
          '${ws.projectDir}/ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
        );
        final stamp = DateTime(2000);
        androidIcon.setLastModifiedSync(stamp);
        iosIcon.setLastModifiedSync(stamp);

        materializeConfig(config: withIcon, workspace: ws, cwd: tmp.path);

        expect(
          androidIcon.lastModifiedSync(),
          stamp,
          reason:
              'an unnecessary mtime bump on an unchanged icon invalidates '
              "Gradle's up-to-date checks",
        );
        expect(
          iosIcon.lastModifiedSync(),
          stamp,
          reason:
              'an unnecessary mtime bump on an unchanged icon invalidates '
              "Xcode's up-to-date checks",
        );
      },
    );
  });
}
