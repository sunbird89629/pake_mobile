import 'dart:io';

import 'package:path/path.dart' as p;

import 'output.dart';

final _unsafeSegment = RegExp(r'[^a-z0-9]+');

/// 唯一的 Flutter 项目实例，Flutter / Gradle / CocoaPods 的增量缓存
/// 长期驻留其中。每次 build 只覆写会变的文件。
class Workspace {
  Workspace({String? root})
    : root =
          root ??
          p.join(
            Platform.environment['HOME'] ?? Directory.current.path,
            '.pake',
          );

  final String root;

  String get projectDir => p.join(root, 'workspace');

  String get lockPath => p.join(root, 'workspace.lock');

  String get logsDir => p.join(root, 'logs');

  String outDirFor(String appName) {
    final slug = appName
        .toLowerCase()
        .replaceAll(_unsafeSegment, '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return p.join(root, 'out', slug.isEmpty ? 'app' : slug);
  }

  void ensureDirs() {
    Directory(projectDir).createSync(recursive: true);
    Directory(p.join(root, 'out')).createSync(recursive: true);
    Directory(logsDir).createSync(recursive: true);
  }

  /// 单 workspace 不支持并行构建两个 app。
  ///
  /// 第二个进程**直接报错退出，不排队**——排队会让 `--json` 的 agent 调用
  /// 静默超时，报错更诚实。
  ///
  /// 异步：`action` 是构建流水线，必须在锁释放前 `await` 完——否则
  /// `finally` 会在 Future 一创建就跑，锁在构建还没完工时就没了。
  Future<T> withLock<T>(Future<T> Function() action) async {
    ensureDirs();
    final lock = File(lockPath);

    if (lock.existsSync()) {
      throw PakeException(
        ExitCodes.environment,
        'Another pakem build holds ${lock.path} (pid '
        '${lock.readAsStringSync().trim()}). Wait for it to finish, or delete '
        'the lock file if that process is gone.',
      );
    }

    lock.writeAsStringSync('$pid');
    try {
      return await action();
    } finally {
      if (lock.existsSync()) lock.deleteSync();
    }
  }
}
