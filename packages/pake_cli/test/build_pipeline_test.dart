import 'dart:io';

import 'package:pake_cli/src/build_pipeline.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.exitCode = 0});

  final int exitCode;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return ProcessResult(0, exitCode, 'stdout', 'stderr');
  }
}

/// Simulates what a real `flutter build` does: it drops a fresh artifact
/// file in the output directory as a side effect of running. Needed to
/// exercise the mtime filter -- [_FakeRunner] never touches the filesystem.
class _WritingFakeRunner implements ProcessRunner {
  _WritingFakeRunner({required this.artifactPath});

  final String artifactPath;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    File(artifactPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('fresh');
    return ProcessResult(0, 0, 'stdout', 'stderr');
  }
}

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
);

void main() {
  group('loadConfigJson', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_cfg'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('prefers an explicit --config path over the cwd file', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{"name":"cwd"}');
      File('${tmp.path}/other.json').writeAsStringSync('{"name":"explicit"}');

      final json = loadConfigJson(
        explicitPath: '${tmp.path}/other.json',
        cwd: tmp.path,
      );

      expect(json['name'], 'explicit');
    });

    test('falls back to pake.json in the cwd', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{"name":"cwd"}');

      expect(loadConfigJson(cwd: tmp.path)['name'], 'cwd');
    });

    test('returns empty when no config file exists', () {
      expect(loadConfigJson(cwd: tmp.path), isEmpty);
    });

    test('errors with exit code 1 when --config points at a missing file', () {
      expect(
        () => loadConfigJson(
          explicitPath: '${tmp.path}/nope.json',
          cwd: tmp.path,
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.config,
          ),
        ),
      );
    });

    test('errors with exit code 1 on malformed json', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{not json');

      expect(
        () => loadConfigJson(cwd: tmp.path),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.config,
          ),
        ),
      );
    });
  });

  group('flutterBuildArgs', () {
    test('android splits per abi and passes version through', () {
      final args = flutterBuildArgs(PakePlatform.android, _config);

      expect(args, containsAllInOrder(['build', 'apk']));
      expect(args, contains('--release'));
      expect(args, contains('--split-per-abi'));
      expect(args, contains('--build-name=2.1.0'));
      expect(args, contains('--build-number=42'));
    });

    test('ios passes the export options plist', () {
      final args = flutterBuildArgs(
        PakePlatform.ios,
        _config,
        exportOptionsPath: '/tmp/ExportOptions.plist',
      );

      expect(args, containsAllInOrder(['build', 'ipa']));
      expect(args, contains('--export-options-plist=/tmp/ExportOptions.plist'));
      expect(args, isNot(contains('--split-per-abi')));
    });

    test('hides the settings page debug items unless asked', () {
      // 默认不带这个 define，pake_shell 的 kShowDebugSettings 在 --release
      // 下就是 false——正式包里 URL / UA / 抓包 / 日志 / 重置 全都不出现。
      final args = flutterBuildArgs(PakePlatform.android, _config);

      expect(args, isNot(contains('--dart-define=PAKE_DEBUG_UI=true')));
    });

    test('--debug-ui keeps them in a release build', () {
      final args = flutterBuildArgs(
        PakePlatform.android,
        _config,
        debugUi: true,
      );

      expect(args, contains('--dart-define=PAKE_DEBUG_UI=true'));
      expect(args, contains('--release'), reason: 'still a release build');
    });
  });

  group('runBuild', () {
    late Directory tmp;
    late Workspace ws;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pakem_build');
      ws = Workspace(root: tmp.path)..ensureDirs();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('invokes flutter build once per requested platform', () async {
      final runner = _FakeRunner();

      await runBuild(
        config: _config,
        platforms: [PakePlatform.android],
        workspace: ws,
        runner: runner,
        output: Output(json: true, sink: StringBuffer()),
      );

      expect(runner.calls.length, 1);
      expect(runner.calls.single.first, 'flutter');
      expect(runner.calls.single, contains('apk'));
    });

    test('throws exit code 3 when flutter build fails', () async {
      final runner = _FakeRunner(exitCode: 1);

      expect(
        () => runBuild(
          config: _config,
          platforms: [PakePlatform.android],
          workspace: ws,
          runner: runner,
          output: Output(json: true, sink: StringBuffer()),
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.build,
          ),
        ),
      );
    });

    test(
      'writes the full build log to the workspace logs dir on failure',
      () async {
        final runner = _FakeRunner(exitCode: 1);

        try {
          await runBuild(
            config: _config,
            platforms: [PakePlatform.android],
            workspace: ws,
            runner: runner,
            output: Output(json: true, sink: StringBuffer()),
          );
        } on PakeException catch (e) {
          expect(
            e.message,
            contains(ws.logsDir),
            reason: 'the terminal must point at the log, per spec',
          );
        }

        final logs = Directory(ws.logsDir).listSync();
        expect(logs, isNotEmpty);
        expect(File(logs.first.path).readAsStringSync(), contains('stderr'));
      },
    );

    test(
      'filters out a stale artifact left behind by a previous app\'s build',
      () async {
        // Workspace is fixed and reused across different apps, and Task
        // 10 forbids cleaning build/ between builds (that would destroy
        // the incremental cache) -- so a stale .apk from a previous app
        // can still be sitting in the output directory.
        final apkDir = p.join(ws.projectDir, 'build/app/outputs/flutter-apk');
        Directory(apkDir).createSync(recursive: true);

        final stalePath = p.join(apkDir, 'old-app-release.apk');
        File(stalePath).writeAsStringSync('stale');
        File(stalePath).setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)),
        );

        final freshPath = p.join(apkDir, 'app-release.apk');
        final runner = _WritingFakeRunner(artifactPath: freshPath);

        final artifacts = await runBuild(
          config: _config,
          platforms: [PakePlatform.android],
          workspace: ws,
          runner: runner,
          output: Output(json: true, sink: StringBuffer()),
        );

        expect(artifacts, [freshPath]);
      },
    );
  });
}
