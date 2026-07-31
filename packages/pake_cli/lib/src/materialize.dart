import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import 'commands/icon.dart';
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

  // `pake_shell/pubspec.yaml` 里 `pake_config: path: ../pake_config` 是
  // 按源码仓库里的兄弟目录关系写的。模板被复制进 `~/.pake/workspace`
  // 后这个相对路径不再指向任何东西——workspace 不在仓库里。固定改写成
  // 指回仓库里 `pake_config` 的绝对路径；两者在仓库里永远是 pake_shell
  // 的兄弟目录，这与 `_resolveTemplateDir` 定位 `pake_shell` 本身用的
  // 是同一个假设。（Task 18 端到端 smoke test 第一次真实构建时发现：
  // 不这么改，`flutter pub get` 在 workspace 里直接失败。）
  final pakeConfigPath = p.normalize(p.join(templateDir, '..', 'pake_config'));

  for (final entity in template.listSync(recursive: true)) {
    if (entity is! File) continue;

    final relative = p.relative(entity.path, from: templateDir);
    if (p.split(relative).any(_cacheDirs.contains)) continue;

    final target = File(p.join(projectDir, relative));
    target.parent.createSync(recursive: true);

    if (relative == 'pubspec.yaml') {
      _writeIfChanged(
        target,
        _rewritePakeConfigPath(entity.readAsStringSync(), pakeConfigPath),
      );
      continue;
    }

    // 内容相同就别写——无谓的 mtime 变化会让 Gradle 判定任务失效。
    //
    // 必须按字节比较，不能解码成字符串：模板树里混着图标、launch image
    // 这类二进制文件，不是合法 UTF-8，`readAsStringSync` 在它们身上会
    // 直接抛 FileSystemException。首次同步时 target 还不存在，走的是
    // 下面的 copySync，不会触发这条比较；真正暴露问题的是固定 workspace
    // 被复用的第二次构建——这正是这个 workspace 存在的意义，所以这条路
    // 径必然会被走到。（同样在 Task 18 的第一次真实构建里发现。）
    if (target.existsSync() &&
        target.lengthSync() == entity.lengthSync() &&
        _bytesEqual(target.readAsBytesSync(), entity.readAsBytesSync())) {
      continue;
    }
    entity.copySync(target.path);
  }
}

String _rewritePakeConfigPath(String pubspec, String absolutePath) {
  return pubspec.replaceFirst(
    RegExp(r'path:\s*\.\./pake_config'),
    'path: $absolutePath',
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
  _writeIfChanged(
    File(p.join(assetsDir.path, 'pake.json')),
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );

  _materializeScripts(config: config, root: root, cwd: cwd);

  // 同步函数只支持本地路径——远程 URL 抓取是异步的，走 `pakem icon` 单独命令。
  final icon = config.iconPath;
  if (icon != null) {
    final bytes = File(
      p.isAbsolute(icon) ? icon : p.join(cwd, icon),
    ).readAsBytesSync();
    writeAndroidIcons(pngBytes: bytes, projectDir: root);
    writeIosIcons(pngBytes: bytes, projectDir: root);
  }
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
  final original = file.readAsStringSync();
  // 已经读过一次原内容了，直接传进去比对，不必让 _writeIfChanged 再读一遍。
  _writeIfChanged(file, patch(original), current: original);
}

/// 只在内容真的变了才写——无谓的 mtime 变化会让 Gradle 的 up-to-date
/// 判定失效，整个固定 workspace 的增量缓存就白搭了。
///
/// [current] 是调用方手上已经有的原内容，传进来能省一次读盘；不传就自己读。
void _writeIfChanged(File file, String content, {String? current}) {
  final existing =
      current ?? (file.existsSync() ? file.readAsStringSync() : null);
  if (existing == content) return;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
