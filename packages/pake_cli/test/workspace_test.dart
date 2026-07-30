import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Workspace ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_ws');
    ws = Workspace(root: tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('ensureDirs creates the workspace and out directories', () {
    ws.ensureDirs();

    expect(Directory(ws.projectDir).existsSync(), isTrue);
    expect(Directory('${tmp.path}/out').existsSync(), isTrue);
  });

  test('outDirFor sanitises app names into a safe directory segment', () {
    expect(ws.outDirFor('My App'), endsWith('/out/my-app'));
    expect(ws.outDirFor('Wei/Bo:2'), endsWith('/out/wei-bo-2'));
  });

  test('withLock runs the action and releases the lock afterwards', () async {
    final result = await ws.withLock(() async => 'done');

    expect(result, 'done');
    expect(
      await ws.withLock(() async => 'again'),
      'again',
      reason: 'a released lock must be re-acquirable',
    );
  });

  test('withLock releases the lock even when the action throws', () async {
    await expectLater(
      () => ws.withLock(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(await ws.withLock(() async => 'recovered'), 'recovered');
  });

  test('a second holder fails immediately instead of queueing', () async {
    ws.ensureDirs();
    File(ws.lockPath).writeAsStringSync('99999');

    await expectLater(
      () => ws.withLock(() async => 'never'),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.environment,
        ),
      ),
    );
  });

  test('the lock is held for the full duration of an async action', () async {
    final future = ws.withLock(() async {
      // 锁必须在这个 await 期间还在——回归会在 Future 创建时就放锁。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        File(ws.lockPath).existsSync(),
        isTrue,
        reason: 'lock must still be held mid-action, after an await',
      );
      return 'done';
    });

    expect(
      File(ws.lockPath).existsSync(),
      isTrue,
      reason: 'lock must be held immediately after withLock is called',
    );

    final result = await future;

    expect(result, 'done');
    expect(
      File(ws.lockPath).existsSync(),
      isFalse,
      reason: 'lock must be released once the action future completes',
    );
  });
}
