import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';

/// 退出码分级——agent 靠它编程处置，不必解析文本。
abstract final class ExitCodes {
  static const config = 1;
  static const environment = 2;
  static const build = 3;
}

/// 携带退出码的失败。CLI 顶层捕获它并交给 [Output.failure]。
class PakeException implements Exception {
  PakeException(this.exitCode, this.message, {this.details = const []});

  final int exitCode;
  final String message;
  final List<ConfigError> details;

  @override
  String toString() => message;
}

/// 唯一的终端出口。
///
/// `--json` 模式下 [info] 被丢弃——进度噪音会污染那个单一 JSON 对象，
/// 而 spec 承诺 `--json` 只输出一个对象。
class Output {
  Output({required this.json, StringSink? sink}) : _sink = sink ?? stdout;

  final bool json;
  final StringSink _sink;

  void info(String line) {
    if (json) return;
    _sink.writeln(line);
  }

  void success(Map<String, Object?> payload) {
    if (json) {
      _sink.write(jsonEncode({'ok': true, ...payload}));
      return;
    }
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value is List) {
        _sink.writeln('${entry.key}:');
        for (final item in value) {
          _sink.writeln('  $item');
        }
      } else {
        _sink.writeln('${entry.key}: $value');
      }
    }
  }

  void failure(PakeException e) {
    if (json) {
      _sink.write(
        jsonEncode({
          'ok': false,
          'error': {
            'exitCode': e.exitCode,
            'message': e.message,
            'details': [for (final d in e.details) d.toJson()],
          },
        }),
      );
      return;
    }
    _sink.writeln('error: ${e.message}');
    for (final d in e.details) {
      _sink.writeln('  - $d');
    }
  }
}
