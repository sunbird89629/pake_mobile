import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import '../build_pipeline.dart';
import '../output.dart';
import '../process_runner.dart';
import '../workspace.dart';

/// 壳里检测更新时按 `<bundleId 末段>-v<semver>` 认 tag，两边必须一致——
/// 改这里就要同步改 `pake_shell/lib/src/update/update_check.dart`。
String tagFor(PakeConfig config) =>
    '${config.bundleId.split('.').last}-v${config.version}';

/// 归档目录里能发布的东西。APK 在前：壳按扩展名筛 `.apk` 取第一个。
List<String> releasableArtifacts(String outDir) {
  final dir = Directory(outDir);
  if (!dir.existsSync()) return const [];

  final files =
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((path) => path.endsWith('.apk') || path.endsWith('.ipa'))
          .toList()
        ..sort();

  return [
    ...files.where((f) => f.endsWith('.apk')),
    ...files.where((f) => f.endsWith('.ipa')),
  ];
}

class ReleaseCommand extends Command<int> {
  ReleaseCommand(this._output, {ProcessRunner? runner, Workspace? workspace})
    : _runner = runner ?? const RealProcessRunner(),
      _workspace = workspace ?? Workspace() {
    argParser
      ..addOption('config')
      ..addOption('notes')
      // 壳的更新检查会跳过 prerelease（见 update_check.dart 的 pickUpdate），
      // 所以发成 prerelease 等于「先放在那儿只给自己装」，在 GitHub 上取消
      // 勾选才推给所有人。
      ..addFlag(
        'prerelease',
        negatable: false,
        help: 'Publish as a pre-release — installed apps will not offer it.',
      )
      // 给 CI 用：一次构建全部 preset，其中多数版本号没动过。这条路径上
      // 「这个版本已经发过了」是常态而不是错误。
      ..addFlag(
        'skip-existing',
        negatable: false,
        help: 'Exit 0 without publishing when the tag already exists.',
      );
  }

  final Output _output;
  final ProcessRunner _runner;
  final Workspace _workspace;

  @override
  String get name => 'release';

  @override
  String get description =>
      'Publish the archived build to GitHub Releases so installed apps can '
      'find it.';

  @override
  String get invocation => 'pakem release [--notes <text>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final json = loadConfigJson(
      explicitPath: args.option('config'),
      cwd: Directory.current.path,
    );
    final config = PakeConfig.fromJson(json);

    // build 能靠命令行补齐 name/bundleId，release 不行：tag 由 bundleId 推、
    // 归档目录由 name 推，两个都得来自那份跟着构建走的 pake.json，猜不得。
    if (config.name.isEmpty || config.bundleId.isEmpty) {
      throw PakeException(
        ExitCodes.config,
        'pake.json needs both name and bundleId to release. '
        'Run `pakem release` from the directory holding the app\'s pake.json.',
      );
    }

    final outDir = _workspace.outDirFor(config.name);
    final artifacts = releasableArtifacts(outDir);

    // 不在这里顺手 build：你应该先把那个 APK 装到真机上验过再发。一发出去
    // 所有用户就会拉下来，而「build 完立刻上传」鼓励的正是发一个没人装过的包。
    if (artifacts.isEmpty) {
      throw PakeException(
        ExitCodes.build,
        'No .apk or .ipa in $outDir — run `pakem build` first, '
        'then install and check that build before releasing it.',
      );
    }

    final tag = tagFor(config);
    final notes = args.option('notes');

    if (args.flag('skip-existing')) {
      final existing = await _runner.run('gh', ['release', 'view', tag]);
      if (existing.exitCode == 0) {
        _output.success({'tag': tag, 'skipped': 'tag already published'});
        return 0;
      }
    }

    final result = await _runner.run('gh', [
      'release',
      'create',
      tag,
      ...artifacts,
      '--title',
      '${config.name} ${config.version}',
      // 自己写了说明就用自己的，否则让 gh 从 commit 生成——两者互斥。
      if (notes != null) ...['--notes', notes] else '--generate-notes',
      if (args.flag('prerelease')) '--prerelease',
    ]);

    if (result.exitCode != 0) {
      // tag 重复、没登录、仓库不对——gh 的报错比我们能猜的更准，原样透出。
      throw PakeException(
        ExitCodes.build,
        'gh release create failed:\n${result.stderr}',
      );
    }

    _output.success({
      'tag': tag,
      'assets': artifacts.map(p.basename).toList(),
      'url': result.stdout.toString().trim(),
      // 发出去的东西用户看不看得见，不该靠人回忆命令行敲了什么。
      'prerelease': args.flag('prerelease'),
    });
    return 0;
  }
}
