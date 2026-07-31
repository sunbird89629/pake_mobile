import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/materialize.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

/// CLI 写出来的东西，壳必须能原样读回去。
///
/// spec 用「schema 物理上不可能漂移」论证 CLI 也用 Dart 写——但共用
/// `PakeConfig` 只保证**字段名**不漂，不保证**字段语义**不漂。Critical 1
/// 就漂在语义上：CLI 往 `index.json` 写 id（`hide-ads`），壳把 `pake.json`
/// 里的原始路径（`hide-ads.js`）当默认启用集合，两边永不相交，注入脚本
/// 端到端全死，而两个包各自的单测全绿。这个文件补的就是那道缝。
void main() {
  late Directory tmp;
  late String templateDir;
  late Workspace ws;

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_contract');
    templateDir = '${tmp.path}/template';
    ws = Workspace(root: '${tmp.path}/pake')..ensureDirs();

    write('$templateDir/lib/main.dart', 'void main() {}');
    write(
      '$templateDir/android/app/build.gradle.kts',
      'android { applicationId = "com.example.pake_shell" }',
    );
    write(
      '$templateDir/android/app/src/main/AndroidManifest.xml',
      '<manifest><application android:label="pake_shell"/></manifest>',
    );
    write('$templateDir/ios/Runner/Info.plist', '''
<plist><dict>
	<key>CFBundleDisplayName</key>
	<string>Pake Shell</string>
</dict></plist>''');
    write(
      '$templateDir/ios/Runner.xcodeproj/project.pbxproj',
      'PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell;',
    );
    write('$templateDir/pubspec.yaml', 'name: pake_shell\n');

    syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the ids the CLI writes are exactly the ids the shell enables by '
      'default, for every shape of --inject path', () {
    // 三种真实会出现的写法：裸文件名、带子目录、绝对路径；且 .js/.css 混用。
    write('${tmp.path}/hide-ads.js', 'document.body.remove();');
    write('${tmp.path}/scripts/theme.css', 'body { background: #000; }');
    write('${tmp.path}/abs/fix-video.js', 'video.play();');

    materializeConfig(
      config: PakeConfig(
        name: 'Weibo',
        url: 'https://m.weibo.cn',
        bundleId: 'com.pake.weibo',
        injectScripts: [
          'hide-ads.js',
          'scripts/theme.css',
          '${tmp.path}/abs/fix-video.js',
        ],
      ),
      workspace: ws,
      cwd: tmp.path,
    );

    // 壳启动时读的两个 asset，原样读回来。
    final buildTime = PakeConfig.fromJson(
      jsonDecode(File('${ws.projectDir}/assets/pake.json').readAsStringSync())
          as Map<String, Object?>,
    );
    final manifest =
        jsonDecode(
              File(
                '${ws.projectDir}/assets/scripts/index.json',
              ).readAsStringSync(),
            )
            as List<Object?>;
    final writtenIds = {
      for (final e in manifest.whereType<Map<String, Object?>>())
        e['id']! as String,
    };

    expect(writtenIds, {
      'hide-ads',
      'theme',
      'fix-video',
    }, reason: 'the ids the CLI actually wrote into index.json');
    // `defaultEnabledScripts` 就是 `RuntimeConfig.enabledScripts` 的回落分支
    // 直接调用的那个函数，不是照抄一份公式。
    expect(
      defaultEnabledScripts(buildTime),
      writtenIds,
      reason:
          'WebViewPage skips any manifest entry whose id is not in this set — '
          'a mismatch means no inject script is ever injected',
    );
  });

  test('every id in index.json has the asset file the shell will load', () {
    write('${tmp.path}/hide-ads.js', 'document.body.remove();');
    write('${tmp.path}/theme.css', 'body { background: #000; }');

    materializeConfig(
      config: const PakeConfig(
        name: 'Weibo',
        url: 'https://m.weibo.cn',
        bundleId: 'com.pake.weibo',
        injectScripts: ['hide-ads.js', 'theme.css'],
      ),
      workspace: ws,
      cwd: tmp.path,
    );

    final manifest =
        jsonDecode(
              File(
                '${ws.projectDir}/assets/scripts/index.json',
              ).readAsStringSync(),
            )
            as List<Object?>;

    for (final entry in manifest.whereType<Map<String, Object?>>()) {
      final id = entry['id']! as String;
      // 壳硬编码地读 `assets/scripts/$id.js`——CSS 也一样，它被包成了 JS。
      expect(
        File('${ws.projectDir}/assets/scripts/$id.js').existsSync(),
        isTrue,
        reason: 'shell loads assets/scripts/$id.js',
      );
    }
  });

  test('a config whose two inject scripts collide on one id never reaches '
      'materialization', () {
    // 物化会让第二个静默盖掉第一个，所以必须在 validateConfig 就拦下。
    write('${tmp.path}/a/theme.js', '// a');
    write('${tmp.path}/b/theme.css', '/* b */');

    final errors = validateConfig(
      PakeConfig(
        name: 'Weibo',
        url: 'https://m.weibo.cn',
        bundleId: 'com.pake.weibo',
        injectScripts: ['${tmp.path}/a/theme.js', '${tmp.path}/b/theme.css'],
      ),
    );

    expect(errors.map((e) => e.field), contains('injectScripts'));
    expect(errors.map((e) => e.message).join(), contains('theme'));
  });
}
