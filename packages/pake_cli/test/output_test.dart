import 'dart:convert';

import 'package:pake_cli/src/output.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

/// 收集写入内容的假 sink。
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

void main() {
  group('Output in human mode', () {
    test('prints info lines', () {
      final b = _Buffer();
      Output(json: false, sink: b).info('building');
      expect(b.buffer.toString(), contains('building'));
    });

    test('prints a readable summary on success', () {
      final b = _Buffer();
      Output(json: false, sink: b).success({
        'artifacts': ['/tmp/app.apk'],
      });
      expect(b.buffer.toString(), contains('/tmp/app.apk'));
      expect(b.buffer.toString(), isNot(startsWith('{')));
    });
  });

  group('Output in json mode', () {
    test('discards info lines so they cannot corrupt the json', () {
      final b = _Buffer();
      Output(json: true, sink: b).info('noise');
      expect(b.buffer.toString(), isEmpty);
    });

    test('emits exactly one json object on success', () {
      final b = _Buffer();
      Output(json: true, sink: b)
        ..info('noise')
        ..success({
          'artifacts': ['/tmp/app.apk'],
        });

      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
      expect((decoded['artifacts']! as List).first, '/tmp/app.apk');
    });

    test('emits a json error object carrying the exit code and details', () {
      final b = _Buffer();
      Output(json: true, sink: b).failure(
        PakeException(
          ExitCodes.config,
          'invalid config',
          details: const [ConfigError('url', 'must be http(s)')],
        ),
      );

      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      final error = decoded['error']! as Map<String, Object?>;
      expect(error['exitCode'], 1);
      expect(error['message'], 'invalid config');
      expect((error['details']! as List).first, {
        'field': 'url',
        'message': 'must be http(s)',
      });
    });
  });
}
