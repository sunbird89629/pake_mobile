import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import 'output.dart';
import 'patch/android.dart';
import 'patch/ios.dart';
import 'patch/scripts.dart';
import 'workspace.dart';

/// 增量缓存所在，同步时必须绕开。
///
/// 复制或删除它们等于每次冷构建——Android 数分钟、iOS 更久，
/// 「一条命令快速出包」就不成立了。
const _cacheDirs = {
  '.dart_tool',
  'build',
  '.gradle',
  'Pods',
  '.git',
  '.symlinks',
};

/// 幂等地把模板同步进固定 workspace：只覆写会变的文件，其余不动。
void syncTemplate({required String templateDir, required String projectDir}) {
  final template = Directory(templateDir);
  for (final entity in template.listSync(recursive: true)) {
    if (entity is! File) continue;

    final relative = p.relative(entity.path, from: templateDir);
    if (p.split(relative).any(_cacheDirs.contains)) continue;

    final target = File(p.join(projectDir, relative));
    target.parent.createSync(recursive: true);

    // 内容相同就别写——无谓的 mtime 变化会让 Gradle 判定任务失效。
    if (target.existsSync() &&
        target.readAsBytesSync().length == entity.lengthSync() &&
        target.readAsStringSync() == entity.readAsStringSync()) {
      continue;
    }
    entity.copySync(target.path);
  }
}

/// 把配置物化进已同步的 workspace。
void materializeConfig({
  required PakeConfig config,
  required Workspace workspace,
  required String cwd,
}) {
  final root = workspace.projectDir;

  _patchFile(
    p.join(root, 'android/app/build.gradle.kts'),
    (s) => patchBuildGradle(s, config),
  );
  _patchFile(
    p.join(root, 'android/app/src/main/AndroidManifest.xml'),
    (s) => patchAndroidManifest(s, config),
  );
  _patchFile(
    p.join(root, 'ios/Runner/Info.plist'),
    (s) => patchInfoPlist(s, config),
  );
  _patchFile(
    p.join(root, 'ios/Runner.xcodeproj/project.pbxproj'),
    (s) => patchPbxproj(s, config),
  );

  // 壳在启动时读它作为运行期默认值。
  final assetsDir = Directory(p.join(root, 'assets'))
    ..createSync(recursive: true);
  File(p.join(assetsDir.path, 'pake.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );

  _materializeScripts(config: config, root: root, cwd: cwd);
}

void _materializeScripts({
  required PakeConfig config,
  required String root,
  required String cwd,
}) {
  final dir = Directory(p.join(root, 'assets/scripts'));
  // 先清空：上一次构建的脚本若留在这里，会被 UserScript 一并注入。
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  final manifest = <Map<String, Object?>>[];
  for (final rawPath in config.injectScripts) {
    final source = File(p.isAbsolute(rawPath) ? rawPath : p.join(cwd, rawPath));
    if (!source.existsSync()) {
      throw PakeException(
        ExitCodes.config,
        'Inject file not found: ${source.path}',
      );
    }

    final script = materializeScript(
      path: source.path,
      content: source.readAsStringSync(),
    );
    File(p.join(dir.path, '${script.id}.js')).writeAsStringSync(script.source);
    manifest.add({'id': script.id, 'kind': script.kind.name});
  }

  File(p.join(dir.path, 'index.json')).writeAsStringSync(jsonEncode(manifest));
}

/// 把 [patch] 套到模板同步已经落地的文件上。
///
/// 缺文件时**必须报错**，不能悄悄跳过：Task 10 的踩坑记录显示，
/// 一旦这四个路径与真实 `flutter create` 输出有一丝出入（比如
/// `build.gradle` vs `build.gradle.kts`），静默跳过会让 bundle id /
/// app 名的配置从未落地，构建照样成功，只是壳里装的是错的应用——
/// 而且这个失败模式不会被任何测试捕获，因为测试用的是同一套假设
/// 搭出来的模板树。宁可在这里让构建炸掉，报出具体缺哪个文件。
void _patchFile(String path, String Function(String) patch) {
  final file = File(path);
  if (!file.existsSync()) {
    throw PakeException(
      ExitCodes.build,
      'Expected template file missing after sync: $path',
    );
  }
  final patched = patch(file.readAsStringSync());
  // 内容没变就不写，保住 Gradle 的 up-to-date 判定。
  if (file.readAsStringSync() == patched) return;
  file.writeAsStringSync(patched);
}
