import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pake_cli/src/commands/build.dart';
import 'package:pake_cli/src/output.dart' show Output, PakeException;
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:test/test.dart';

void _write(String path, String content) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

/// 从不触碰真实文件系统的假 runner——这些测试要验证的是 `withLock`
/// 回调里同步 + 物化跑没跑，不是真的调 flutter build。
class _FakeRunner implements ProcessRunner {
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return ProcessResult(0, 0, 'stdout', 'stderr');
  }
}

/// runner.dart 里的 `buildRunner` 是生产环境的装配线，不接受注入的
/// workspace / runner / templateDir。这里搭一个只挂了待测 [command] 的
/// 迷你 `CommandRunner`，走真实的 args 解析，但依赖全是假的——
/// 这样才能不依赖 `pake_shell`（Task 12 还没建）单独冻住 Task 10 的接线。
void main() {
  late Directory tmp;
  late String templateDir;
  late Workspace ws;
  late _FakeRunner runner;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_buildcmd');
    templateDir = '${tmp.path}/template';
    ws = Workspace(root: '${tmp.path}/pake')..ensureDirs();
    runner = _FakeRunner();

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
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  CommandRunner<int> runnerFor(BuildCommand command) =>
      CommandRunner<int>('pakem', 'test')..addCommand(command);

  test('run() syncs the template and materializes the config into the '
      'workspace before building', () async {
    final output = Output(json: true, sink: StringBuffer());
    final command = BuildCommand(
      output,
      runner: runner,
      workspace: ws,
      templateDir: templateDir,
    );

    final code = await runnerFor(command).run([
      'build',
      'https://m.weibo.cn',
      '--name',
      'Weibo',
      '--bundle-id',
      'com.pake.weibo',
    ]);

    expect(code, 0);

    // synced
    expect(File('${ws.projectDir}/lib/main.dart').existsSync(), isTrue);

    // materialized
    expect(
      File('${ws.projectDir}/android/app/build.gradle.kts').readAsStringSync(),
      contains('com.pake.weibo'),
    );
    final pakeJson =
        jsonDecode(File('${ws.projectDir}/assets/pake.json').readAsStringSync())
            as Map<String, Object?>;
    expect(pakeJson['name'], 'Weibo');

    // and only after both of the above did the build actually run
    expect(runner.calls, isNotEmpty);
  });

  test('sync + materialize run inside withLock, so a held lock blocks the '
      'whole build', () async {
    File(ws.lockPath).writeAsStringSync('12345');
    final output = Output(json: true, sink: StringBuffer());
    final command = BuildCommand(
      output,
      runner: runner,
      workspace: ws,
      templateDir: templateDir,
    );

    await expectLater(
      runnerFor(command).run([
        'build',
        'https://m.weibo.cn',
        '--name',
        'Weibo',
        '--bundle-id',
        'com.pake.weibo',
      ]),
      throwsA(isA<PakeException>()),
    );

    expect(
      File('${ws.projectDir}/lib/main.dart').existsSync(),
      isFalse,
      reason: 'a held lock must block sync/materialize too, not just build',
    );
    expect(runner.calls, isEmpty);
  });
}
