import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import 'output.dart';
import 'process_runner.dart';
import 'workspace.dart';

enum PakePlatform {
  android,
  ios;

  static PakePlatform byName(String name) {
    for (final v in PakePlatform.values) {
      if (v.name == name) return v;
    }
    throw PakeException(
      ExitCodes.config,
      'Unknown platform "$name"; expected android or ios.',
    );
  }
}

/// spec 的查找顺序：`--config` > cwd 的 `pake.json` > 无文件。
/// 三者**不叠加**，取第一个命中的来源。
Map<String, Object?> loadConfigJson({
  String? explicitPath,
  required String cwd,
}) {
  final File file;
  if (explicitPath != null) {
    file = File(explicitPath);
    if (!file.existsSync()) {
      throw PakeException(
        ExitCodes.config,
        'Config file not found: $explicitPath',
      );
    }
  } else {
    file = File(p.join(cwd, 'pake.json'));
    if (!file.existsSync()) return const {};
  }

  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    throw PakeException(
      ExitCodes.config,
      'Could not parse ${file.path} as JSON: $e',
    );
  }
}

List<String> flutterBuildArgs(
  PakePlatform platform,
  PakeConfig config, {
  String? exportOptionsPath,
}) {
  final common = [
    '--release',
    '--build-name=${config.version}',
    '--build-number=${config.buildNumber}',
  ];

  return switch (platform) {
    PakePlatform.android => ['build', 'apk', ...common, '--split-per-abi'],
    PakePlatform.ios => [
      'build',
      'ipa',
      ...common,
      if (exportOptionsPath != null)
        '--export-options-plist=$exportOptionsPath',
    ],
  };
}

/// 逐个平台调 `flutter build`，返回产物路径。
///
/// 失败时全量输出落 `~/.pake/logs/`，终端只给关键行 + 日志路径——
/// gradle 那几千行刷屏对定位问题毫无帮助。
Future<List<String>> runBuild({
  required PakeConfig config,
  required List<PakePlatform> platforms,
  required Workspace workspace,
  required ProcessRunner runner,
  required Output output,
  String? exportOptionsPath,
}) async {
  final artifacts = <String>[];
  // Workspace is a single persistent project reused across different apps
  // and never cleaned between builds (that would destroy the incremental
  // cache). So `build/` can still hold a *previous* app's .apk/.ipa —
  // filter by mtime so we never hand back someone else's artifact.
  final buildStart = DateTime.now();

  for (final platform in platforms) {
    output.info('Building ${platform.name}…');

    final args = flutterBuildArgs(
      platform,
      config,
      exportOptionsPath: exportOptionsPath,
    );
    final result = await runner.run(
      'flutter',
      args,
      workingDirectory: workspace.projectDir,
    );

    if (result.exitCode != 0) {
      final logPath = _writeBuildLog(workspace, platform, args, result);
      throw PakeException(
        ExitCodes.build,
        'flutter ${args.join(' ')} failed with exit code ${result.exitCode}.\n'
        '${_lastLines(result.stderr.toString(), 10)}\n'
        'Full output: $logPath',
      );
    }

    artifacts.addAll(_collectArtifacts(workspace, platform, since: buildStart));
  }

  return artifacts;
}

String _writeBuildLog(
  Workspace workspace,
  PakePlatform platform,
  List<String> args,
  ProcessResult result,
) {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final path = p.join(workspace.logsDir, 'build-${platform.name}-$stamp.log');
  File(path).writeAsStringSync('''
\$ flutter ${args.join(' ')}
exit code: ${result.exitCode}

--- stdout ---
${result.stdout}

--- stderr ---
${result.stderr}
''');
  return path;
}

String _lastLines(String text, int count) {
  final lines = text.trimRight().split('\n');
  return lines
      .sublist(lines.length > count ? lines.length - count : 0)
      .join('\n');
}

// Some filesystems only keep 1-second mtime resolution, so a file written
// right at (or just before, after rounding) `since` could otherwise be
// wrongly discarded. A couple of seconds of slack costs nothing here —
// stale artifacts from a genuinely earlier build are still minutes/hours
// old, not a couple of seconds.
const _mtimeTolerance = Duration(seconds: 2);

List<String> _collectArtifacts(
  Workspace workspace,
  PakePlatform platform, {
  required DateTime since,
}) {
  final dir = switch (platform) {
    PakePlatform.android => Directory(
      p.join(workspace.projectDir, 'build/app/outputs/flutter-apk'),
    ),
    PakePlatform.ios => Directory(
      p.join(workspace.projectDir, 'build/ios/ipa'),
    ),
  };

  if (!dir.existsSync()) return const [];

  final cutoff = since.subtract(_mtimeTolerance);
  final wanted = platform == PakePlatform.android ? '.apk' : '.ipa';
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => !f.lastModifiedSync().isBefore(cutoff))
      .map((f) => f.path)
      .where((path) => path.endsWith(wanted))
      .toList()
    ..sort();
}
