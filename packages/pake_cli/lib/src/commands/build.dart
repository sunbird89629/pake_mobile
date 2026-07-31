import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import '../build_pipeline.dart';
import '../materialize.dart';
import '../output.dart';
import '../patch/ios.dart';
import '../process_runner.dart';
import '../signing.dart';
import '../workspace.dart';

class BuildCommand extends Command<int> {
  BuildCommand(
    this._output, {
    ProcessRunner? runner,
    Workspace? workspace,
    String? templateDir,
  }) : _runner = runner ?? const RealProcessRunner(),
       _workspace = workspace ?? Workspace(),
       _templateDirOverride = templateDir {
    argParser
      // 默认 android：iOS 需要签名参数，静默尝试双端后失败会让首次
      // 使用者困惑。要 iOS 就显式写出来。
      ..addOption('platform', defaultsTo: 'android')
      ..addOption('config')
      ..addOption('name')
      ..addOption('icon')
      ..addOption('bundle-id')
      ..addOption('version')
      ..addOption('team-id')
      ..addOption('profile')
      ..addMultiOption('inject');
  }

  final Output _output;
  final ProcessRunner _runner;
  final Workspace _workspace;
  final String? _templateDirOverride;

  @override
  String get name => 'build';

  @override
  String get description => 'Build the given URL into an app.';

  @override
  String get invocation => 'pakem build <url> [options]';

  /// `pake_shell` 模板包的路径。
  ///
  /// 不用 `Platform.script`——在 `dart test` 下它指向一个临时 `.dill`
  /// 文件，不是源码位置。`package:pake_cli/` 经 package_config.json
  /// 解析到 `pake_cli/lib/`，在 isolate 启动时就固定好，测试和真正
  /// 安装的 CLI（`dart pub global activate --source path`）下都成立。
  /// `pake_shell` 是 Flutter 包、不是 pake_cli 的依赖，没法直接用
  /// `package:pake_shell/` 解析，只能从 `pake_cli/lib/` 相对上溯。
  Future<String> _resolveTemplateDir() async {
    final override = _templateDirOverride;
    if (override != null) return override;

    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:pake_cli/'),
    );
    return p.normalize(p.join(libUri!.toFilePath(), '..', '..', 'pake_shell'));
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final url = args.rest.isEmpty ? null : args.rest.first;

    final config = mergeConfig(
      fileJson: loadConfigJson(
        explicitPath: args.option('config'),
        cwd: Directory.current.path,
      ),
      flags: PakeFlags(
        name: args.option('name'),
        url: url,
        bundleId: args.option('bundle-id'),
        version: args.option('version'),
        iconPath: args.option('icon'),
        injectScripts: args.wasParsed('inject')
            ? args.multiOption('inject')
            : null,
      ),
    );

    final errors = validateConfig(config);
    if (errors.isNotEmpty) {
      throw PakeException(
        ExitCodes.config,
        'Invalid configuration (${errors.length} problem(s)).',
        details: errors,
      );
    }

    final platforms = args
        .option('platform')!
        .split(',')
        .map((s) => PakePlatform.byName(s.trim()))
        .toList();

    String? exportOptionsPath;
    if (platforms.contains(PakePlatform.ios)) {
      final teamId = args.option('team-id');
      final profileName = args.option('profile');
      if (teamId == null || profileName == null) {
        throw PakeException(
          ExitCodes.config,
          'iOS builds need --team-id and --profile.',
        );
      }

      await checkIosSigning(
        runner: _runner,
        profileName: profileName,
        bundleId: config.bundleId,
        profiles: await loadInstalledProfiles(_runner),
      );

      exportOptionsPath = p.join(_workspace.root, 'ExportOptions.plist');
      File(exportOptionsPath).writeAsStringSync(
        exportOptionsPlist(
          teamId: teamId,
          profileName: profileName,
          bundleId: config.bundleId,
        ),
      );
    }

    final templateDir = await _resolveTemplateDir();

    final artifacts = await _workspace.withLock(() async {
      syncTemplate(templateDir: templateDir, projectDir: _workspace.projectDir);
      materializeConfig(
        config: config,
        workspace: _workspace,
        cwd: Directory.current.path,
        templateDir: templateDir,
      );

      return runBuild(
        config: config,
        platforms: platforms,
        workspace: _workspace,
        runner: _runner,
        output: _output,
        exportOptionsPath: exportOptionsPath,
      );
    });

    _output.success({'app': config.name, 'artifacts': artifacts});
    return 0;
  }
}
