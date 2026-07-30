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

  test('withLock runs the action and releases the lock afterwards', () {
    final result = ws.withLock(() => 'done');

    expect(result, 'done');
    expect(
      ws.withLock(() => 'again'),
      'again',
      reason: 'a released lock must be re-acquirable',
    );
  });

  test('withLock releases the lock even when the action throws', () {
    expect(() => ws.withLock(() => throw StateError('boom')), throwsStateError);

    expect(ws.withLock(() => 'recovered'), 'recovered');
  });

  test('a second holder fails immediately instead of queueing', () {
    ws.ensureDirs();
    File(ws.lockPath).writeAsStringSync('99999');

    expect(
      () => ws.withLock(() => 'never'),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.environment,
        ),
      ),
    );
  });
}
