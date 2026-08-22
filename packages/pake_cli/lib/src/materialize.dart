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

/// `materializeConfig` 会从模板原始内容重新生成的四个补丁目标。
const _patchTargets = [
  'android/app/build.gradle.kts',
  'android/app/src/main/AndroidManifest.xml',
  'ios/Runner/Info.plist',
  'ios/Runner.xcodeproj/project.pbxproj',
];

/// 这条路径归 `materializeConfig` 管，`syncTemplate` 必须绕开。
///
/// 两个函数在每次构建里连着跑。sync 拿 workspace 里**已经打过补丁**的文件
/// 跟模板的原始文件比，两者永远不相等，于是把补丁覆盖掉；紧接着
/// materializeConfig 再打一遍补丁写回去。结果是每次「什么都没改」的重建都
/// 有一批文件被写入字节完全相同的内容——`_writeIfChanged` 从来没有真正生效
/// 过，而幂等性测试却是绿的，因为它把 syncTemplate 放进 setUp，测的是生产
/// 环境从不会跑的调用顺序。
///
/// 划清归属之后，补丁永远从干净的模板内容开始打（不会跨次构建累积漂移），
/// `_writeIfChanged` 也终于有事可做。
bool _ownedByMaterialize(String relative) {
  final parts = p.split(relative);
  if (_patchTargets.any((t) => t == p.joinAll(parts))) return true;

  // pake.json 与 assets/scripts/ 整棵子树都是物化产物；图标要么由 --icon
  // 写入，要么由 restoreTemplateIcons 从模板取回，两条路都归 materialize。
  if (parts.length >= 2 && parts.first == 'assets') {
    return parts[1] == 'pake.json' || parts[1] == 'scripts';
  }
  return iconRelativePaths().contains(p.joinAll(parts));
}

/// 幂等地把模板同步进固定 workspace：只覆写会变的文件，其余不动。
void syncTemplate({required String templateDir, required String projectDir}) {
  final template = Directory(templateDir);

  for (final entity in template.listSync(recursive: true)) {
    if (entity is! File) continue;

    final relative = p.relative(entity.path, from: templateDir);
    if (p.split(relative).any(_cacheDirs.contains)) continue;
    if (_ownedByMaterialize(relative)) continue;

    final target = File(p.join(projectDir, relative));
    target.parent.createSync(recursive: true);

    if (relative == 'pubspec.yaml') {
      _writeIfChanged(
        target,
        _rewriteSiblingPaths(entity.readAsStringSync(), templateDir),
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

/// 把 `pubspec.yaml` 里所有 `path: ../x` 的本地依赖改写成绝对路径。
///
/// 这些相对路径是按源码仓库里的兄弟目录关系写的。模板被复制进
/// `~/.pake/workspace` 后它们不再指向任何东西——workspace 不在仓库里，
/// `flutter pub get` 会直接失败。仓库里 pake_shell 的兄弟目录关系是稳定的，
/// 这与 `_resolveTemplateDir` 定位 `pake_shell` 本身用的是同一个假设。
/// （Task 18 端到端 smoke test 第一次真实构建时发现。）
///
/// **按模式改写，不是列举包名**：原来只认死了 `../pake_config`，
/// 后来 pake_shell 加了 `pake_cli: path: ../pake_cli` 这个 dev 依赖，
/// 本地构建就此静默坏掉——而单元测试全绿，因为没有一条测试真的跑 pub get。
/// 再往 pubspec 里加兄弟依赖时不该重蹈一次。
String _rewriteSiblingPaths(String pubspec, String templateDir) {
  return pubspec.replaceAllMapped(
    RegExp(r'path:\s*(\.\./[^\s#]+)'),
    (m) => 'path: ${p.normalize(p.join(templateDir, m[1]!))}',
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
///
/// [templateDir] 是 `syncTemplate` 用的同一个模板目录：没配图标时要从这里
/// 取回默认图标。
void materializeConfig({
  required PakeConfig config,
  required Workspace workspace,
  required String cwd,
  required String templateDir,
}) {
  final root = workspace.projectDir;

  final patches = <String, String Function(String)>{
    'android/app/build.gradle.kts': (s) => patchBuildGradle(s, config),
    'android/app/src/main/AndroidManifest.xml': (s) =>
        patchAndroidManifest(s, config),
    'ios/Runner/Info.plist': (s) => patchInfoPlist(s, config),
    'ios/Runner.xcodeproj/project.pbxproj': (s) => patchPbxproj(s, config),
  };
  assert(
    patches.keys.every(_patchTargets.contains) &&
        patches.length == _patchTargets.length,
    'syncTemplate skips exactly _patchTargets — the two lists must agree, '
    'or a target either never gets synced or gets its patch overwritten',
  );
  for (final entry in patches.entries) {
    _patchFromTemplate(
      templateDir: templateDir,
      projectDir: root,
      relative: entry.key,
      patch: entry.value,
    );
  }

  // 壳在启动时读它作为运行期默认值。
  final assetsDir = Directory(p.join(root, 'assets'))
    ..createSync(recursive: true);
  _writeIfChanged(
    File(p.join(assetsDir.path, 'pake.json')),
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );

  materializeScriptsInto(
    config: config,
    outDir: Directory(p.join(root, 'assets/scripts')),
    cwd: cwd,
  );

  // 同步函数只支持本地路径——远程 URL 抓取是异步的，走 `pakem icon` 单独命令。
  final icon = config.iconPath;
  if (icon != null) {
    final bytes = File(
      p.isAbsolute(icon) ? icon : p.join(cwd, icon),
    ).readAsBytesSync();
    writeAndroidIcons(pngBytes: bytes, projectDir: root);
    writeIosIcons(pngBytes: bytes, projectDir: root);
  } else {
    // 没配图标 ≠ 什么都不做：workspace 里可能还留着上一个 app 的图标。
    restoreTemplateIcons(templateDir: templateDir, projectDir: root);
  }
}

/// 把 [config] 的 `injectScripts` 物化进 [outDir]。
///
/// 构建期与开发期共用**同一个函数**：前者由 [materializeConfig] 写进
/// workspace，后者由 `pake_shell/tool/dev_scripts.dart` 直接写进模板仓库的
/// `assets/scripts/`。id 规则一旦各写一份，壳算出的启用集合就会跟物化产物
/// 对不上，而且两边的测试都能是绿的——见 `pake_config` 的 `script_id.dart`。
///
/// [preserve] 里的文件名不参与「删除上一次构建的残留」。开发期要靠它保住
/// `.gitkeep`：那是签入仓库的文件，被当成残留删掉就等于改动了工作区。
void materializeScriptsInto({
  required PakeConfig config,
  required Directory outDir,
  required String cwd,
  Set<String> preserve = const {},
}) {
  final dir = outDir..createSync(recursive: true);

  final manifest = <Map<String, Object?>>[];
  // 这一轮该留在目录里的文件。其余的都是上一次构建的残留——留着会被
  // UserScript 一并注入。
  final wanted = <String>{'index.json', ...preserve};

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
    final name = '${script.id}.js';
    wanted.add(name);
    // 整个目录 delete 再重写，等于每次构建都刷新一批 mtime——跟 pake.json
    // 和四个补丁目标一样走 _writeIfChanged，只删真正多余的文件。
    _writeIfChanged(File(p.join(dir.path, name)), script.source);
    manifest.add({'id': script.id, 'kind': script.kind.name});
  }

  _writeIfChanged(File(p.join(dir.path, 'index.json')), jsonEncode(manifest));

  for (final stale in dir.listSync().whereType<File>()) {
    if (!wanted.contains(p.basename(stale.path))) stale.deleteSync();
  }
}

/// 从**模板**里取原始内容，打上 [patch]，写进 workspace。
///
/// 读模板而不是读 workspace：workspace 里那份已经打过补丁了，拿它当输入意味
/// 着补丁叠补丁，跨次构建可能积累漂移；而且 syncTemplate 已经不再同步这些
/// 路径，workspace 里的那份在第一次构建时压根不存在。
///
/// 缺文件时**必须报错**，不能悄悄跳过：Task 10 的踩坑记录显示，
/// 一旦这四个路径与真实 `flutter create` 输出有一丝出入（比如
/// `build.gradle` vs `build.gradle.kts`），静默跳过会让 bundle id /
/// app 名的配置从未落地，构建照样成功，只是壳里装的是错的应用——
/// 而且这个失败模式不会被任何测试捕获，因为测试用的是同一套假设
/// 搭出来的模板树。宁可在这里让构建炸掉，报出具体缺哪个文件。
void _patchFromTemplate({
  required String templateDir,
  required String projectDir,
  required String relative,
  required String Function(String) patch,
}) {
  final source = File(p.join(templateDir, relative));
  if (!source.existsSync()) {
    throw PakeException(
      ExitCodes.build,
      'Expected template file missing: ${source.path}',
    );
  }
  _writeIfChanged(
    File(p.join(projectDir, relative)),
    patch(source.readAsStringSync()),
  );
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
