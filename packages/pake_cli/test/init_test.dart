import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/commands/init.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_init'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('writes a pake.json template that parses back into a PakeConfig', () {
    writeInitTemplate(tmp.path);

    final file = File('${tmp.path}/pake.json');
    expect(file.existsSync(), isTrue);

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final config = PakeConfig.fromJson(decoded);

    expect(config.name, isNotEmpty);
    expect(
      validateConfig(config, fileExists: (_) => true),
      isEmpty,
      reason: 'the template we ship must itself be valid',
    );
  });

  test('refuses to clobber an existing pake.json', () {
    File('${tmp.path}/pake.json').writeAsStringSync('{"name":"mine"}');

    expect(
      () => writeInitTemplate(tmp.path),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.config,
        ),
      ),
    );

    expect(File('${tmp.path}/pake.json').readAsStringSync(), contains('mine'));
  });
}
