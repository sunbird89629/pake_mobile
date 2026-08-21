import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pake_cli/src/commands/release.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

/// 记下 gh 被怎么调的，不真的发布。
class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.exitCode = 0, this.stderr = ''});

  final calls = <List<String>>[];
  final int exitCode;
  final String stderr;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return ProcessResult(
      0,
      exitCode,
      'https://github.com/o/r/releases/x',
      stderr,
    );
  }
}

void main() {
  late Directory tmp;
  late Workspace ws;
  late _FakeRunner runner;
  late StringBuffer out;

  /// 归档目录由 app 名推导，跟 `pakem build` 落盘的是同一个函数。
  void archive(String appName, List<String> files) {
    final dir = Directory(ws.outDirFor(appName))..createSync(recursive: true);
    for (final name in files) {
      File('${dir.path}/$name').writeAsStringSync('binary');
    }
  }

  void writeConfig(Map<String, Object?> json) =>
      File('${tmp.path}/pake.json').writeAsStringSync(jsonEncode(json));

  /// `buildRunner` 是生产装配线，不接受注入；这里搭一个只挂了待测命令的
  /// 迷你 runner，走真实的 args 解析但依赖全是假的。
  Future<int> run(List<String> args, {_FakeRunner? withRunner}) async {
    final cr = CommandRunner<int>('pakem', '')
      ..addCommand(
        ReleaseCommand(
          Output(json: false, sink: out),
          runner: withRunner ?? runner,
          workspace: ws,
        ),
      );

    return await cr.run([
          'release',
          '--config',
          '${tmp.path}/pake.json',
          ...args,
        ]) ??
        0;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_release');
    ws = Workspace(root: '${tmp.path}/pake')..ensureDirs();
    runner = _FakeRunner();
    out = StringBuffer();

    writeConfig({
      'name': '4KVM',
      'url': 'https://www.4kvm.site',
      'bundleId': 'com.pake.fourkvm',
      'version': '1.2.0',
    });
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('tagFor', () {
    // 壳按同样的规则筛 release，两边对不上就是静默失效。
    test('is the bundle id tail plus v-semver', () {
      expect(
        tagFor(
          const PakeConfig(
            name: '4KVM',
            url: 'https://x',
            bundleId: 'com.pake.fourkvm',
            version: '1.2.0',
          ),
        ),
        'fourkvm-v1.2.0',
      );
    });
  });

  group('releasableArtifacts', () {
    test('puts the apk first — the shell takes the first .apk it sees', () {
      archive('4KVM', ['4kvm.ipa', '4kvm.apk', 'build.log']);

      final found = releasableArtifacts(ws.outDirFor('4KVM'));

      expect(found.map((f) => f.split('/').last), ['4kvm.apk', '4kvm.ipa']);
    });

    test('is empty when the app was never built', () {
      expect(releasableArtifacts('${tmp.path}/nope'), isEmpty);
    });
  });

  test('uploads the archived artifacts under the derived tag', () async {
    archive('4KVM', ['4kvm.apk']);

    expect(await run([]), 0);
    expect(runner.calls.single.take(3), ['gh', 'release', 'create']);
    expect(runner.calls.single[3], 'fourkvm-v1.2.0');
    expect(runner.calls.single, contains(endsWith('4kvm.apk')));
    expect(runner.calls.single, contains('--generate-notes'));
  });

  test('own notes replace the generated ones', () async {
    archive('4KVM', ['4kvm.apk']);

    await run(['--notes', '修了 X']);

    expect(runner.calls.single, contains('修了 X'));
    expect(runner.calls.single, isNot(contains('--generate-notes')));
  });

  // 发布前应该先把那个包装到真机上验过——这里报错比默默 build 一个新包好。
  test('refuses to release what was never built', () async {
    expect(
      run([]),
      throwsA(
        isA<PakeException>()
            .having((e) => e.exitCode, 'exitCode', ExitCodes.build)
            .having((e) => e.message, 'message', contains('pakem build')),
      ),
    );
  });

  test('surfaces gh failures verbatim, including duplicate tags', () async {
    archive('4KVM', ['4kvm.apk']);
    final failing = _FakeRunner(
      exitCode: 1,
      stderr: 'a release with tag fourkvm-v1.2.0 already exists',
    );

    expect(
      run([], withRunner: failing),
      throwsA(
        isA<PakeException>().having(
          (e) => e.message,
          'message',
          contains('already exists'),
        ),
      ),
    );
  });

  test('needs a name and bundle id it can trust', () async {
    writeConfig({'url': 'https://www.4kvm.site'});

    expect(
      run([]),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.config,
        ),
      ),
    );
  });
}
