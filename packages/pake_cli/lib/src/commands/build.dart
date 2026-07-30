import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pake_config/pake_config.dart';

import '../build_pipeline.dart';
import '../output.dart';
import '../process_runner.dart';
import '../workspace.dart';

class BuildCommand extends Command<int> {
  BuildCommand(this._output, {ProcessRunner? runner, Workspace? workspace})
    : _runner = runner ?? const RealProcessRunner(),
      _workspace = workspace ?? Workspace() {
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

  @override
  String get name => 'build';

  @override
  String get description => 'Build the given URL into an app.';

  @override
  String get invocation => 'pakem build <url> [options]';

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

    final artifacts = await _workspace.withLock(() async {
      // Task 10 会在这里插入 workspace 同步 + 物化；
      // 现在先直接构建，好让这一步独立可测。
      return runBuild(
        config: config,
        platforms: platforms,
        workspace: _workspace,
        runner: _runner,
        output: _output,
      );
    });

    _output.success({'app': config.name, 'artifacts': artifacts});
    return 0;
  }
}
