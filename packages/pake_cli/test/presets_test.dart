import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `presets/` 是给用户装机的预构建 app 的真相源，但它在 pake_cli 的上级
/// 目录，`dart test` 从不把它当代码走一遍——路径写错、脚本 id 撞车、json
/// 拼错都只会在 CI 真正跑 build-presets 时才炸，反馈太晚。这里把校验提前。
void main() {
  final repoRoot = _findRepoRoot(Directory.current);
  final presetsDir = Directory(p.join(repoRoot, 'presets'));

  final presets =
      presetsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('presets/ 至少有一个站点，否则下面这条校验空转', () {
    expect(presets, isNotEmpty);
  });

  for (final file in presets) {
    group('preset ${p.basename(file.path)}', () {
      final config = PakeConfig.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );

      test('name / url / bundleId 齐全', () {
        expect(config.name, isNotEmpty);
        expect(Uri.parse(config.url).host, isNotEmpty);
        expect(config.bundleId, isNotEmpty);
      });

      test('injectScripts 每条都指向仓库根下真实存在的非空文件，id 不撞车', () {
        final ids = <String>{};
        for (final raw in config.injectScripts) {
          final abs = p.isAbsolute(raw) ? raw : p.join(repoRoot, raw);
          final f = File(abs);
          expect(f.existsSync(), isTrue, reason: '$raw 不存在');
          expect(f.readAsStringSync(), isNotEmpty, reason: '$raw 是空的');

          final id = scriptIdFor(raw);
          expect(ids.add(id), isTrue, reason: '脚本 id "$id" 重复，后写的会盖掉前一个');
        }
      });
    });
  }
}

/// 从 [start] 往上找包含 `presets/` 的目录——`dart test` 的 cwd 是包目录，
/// 但别把「从仓库根跑」这种意外情况变成静默失败。
String _findRepoRoot(Directory start) {
  var dir = start;
  while (true) {
    if (Directory(p.join(dir.path, 'presets')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return start.path;
    dir = parent;
  }
}
