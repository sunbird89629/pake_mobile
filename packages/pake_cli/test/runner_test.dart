import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/runner.dart';
import 'package:test/test.dart';

/// 收集写入内容的假 sink，同 output_test.dart。
class _Buffer implements StringSink {
  final buffer = StringBuffer();
  @override
  void write(Object? obj) => buffer.write(obj);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);
  @override
  void writeln([Object? obj = '']) => buffer.writeln(obj);
}

/// 这些测试驱动真实的 `CommandRunner`（而不是像 init_test.dart 那样直接调
/// `writeInitTemplate`），专门覆盖 `--json` 是否被 `buildRunner` 的
/// `argParser` 识别——`args` 包会拒绝任何未声明的 flag，声明缺失时整条
/// `pakem <cmd> --json` 命令行在真正跑到业务逻辑前就已经解析失败。
void main() {
  late Directory tmp;
  late Directory original;

  setUp(() {
    original = Directory.current;
    tmp = Directory.systemTemp.createTempSync('pakem_runner');
    Directory.current = tmp;
  });

  tearDown(() {
    Directory.current = original;
    tmp.deleteSync(recursive: true);
  });

  test(
    '`init --json` parses and runs end-to-end, emitting one json object',
    () async {
      final b = _Buffer();
      final output = Output(json: true, sink: b);

      final code = await buildRunner(output).run(['init', '--json']);

      expect(code, 0);
      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
    },
  );

  test(
    '`--json init` (flag before the subcommand) also parses and runs',
    () async {
      final b = _Buffer();
      final output = Output(json: true, sink: b);

      final code = await buildRunner(output).run(['--json', 'init']);

      expect(code, 0);
      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
    },
  );
}
