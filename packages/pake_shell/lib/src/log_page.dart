import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 读回 `logger_utils` 落盘的 daily-rotated 日志文件。
///
/// `initLogging` 不传 `logsDir` 时压根不写文件（见其 `_fileSink`：
/// `dir == null` 直接 return），所以这里必须收到 `main.dart` 显式传下来的
/// 同一个目录——不能猜 `Directory.current`，那是桌面语义，移动端从来不是
/// 日志落盘的地方。`logsDir` 为 `null` 时（例如 widget 测试里没有配置）
/// 就诚实地说明日志未配置，而不是抛异常或读到无关文件。
class LogPage extends StatelessWidget {
  const LogPage({super.key, required this.logsDir});

  final String? logsDir;

  Future<String> _read() async {
    final dir = logsDir;
    if (dir == null) return 'Logging is not configured.';

    final directory = Directory(dir);
    if (!directory.existsSync()) return 'No log files yet.';

    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.log'))
            .toList()
          // 按文件名倒排——`logger_utils` 用 `<prefix>-YYYY-MM-DD.log` 命名，
          // 字符串序即日期序，最新的排最前。
          ..sort((a, b) => b.path.compareTo(a.path));

    if (files.isEmpty) return 'No log files yet.';
    return files.first.readAsStringSync();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _read(),
      builder: (context, snapshot) {
        final content = snapshot.hasError
            ? 'Could not read logs: ${snapshot.error}'
            : snapshot.data ?? 'Loading…';
        final loaded = snapshot.connectionState == ConnectionState.done;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Logs'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: loaded
                    ? () => Clipboard.setData(ClipboardData(text: content))
                    : null,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}
