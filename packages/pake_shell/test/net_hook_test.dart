import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `assets/net_hook.js` 是注进 WebView 的真 JS，Dart 侧没法直接调用它。
/// 用 node 跑 `test/net_hook_harness.js`：那个宿主搭出最小的 window /
/// fetch / XMLHttpRequest，加载**同一份** asset，跑一组场景并回报每条记录
/// 以及 body 被读进内存的次数。
///
/// `bodyReads` 是这组测试的核心。只断言 body 的内容不够——「先把整个响应
/// 读进来、再把结果换成一句说明」同样能通过内容断言，却依然会在流式大响应
/// 上把 WebView 撑爆。要证明的是那次读**根本没有发生**。
void main() {
  late Map<String, Map<String, Object?>> cases;

  setUpAll(() {
    final result = Process.runSync('node', [
      'test/net_hook_harness.js',
      'assets/net_hook.js',
    ], workingDirectory: Directory.current.path);

    expect(
      result.exitCode,
      0,
      reason: 'net_hook harness failed:\n${result.stderr}',
    );

    cases = {
      for (final entry
          in (jsonDecode(result.stdout as String) as List<Object?>)
              .cast<Map<String, Object?>>())
        entry['name']! as String: entry,
    };
  });

  String bodyOf(String name) =>
      (cases[name]!['record']! as Map<String, Object?>)['body']! as String;
  int bodyReadsOf(String name) => cases[name]!['bodyReads']! as int;

  group('fetch hook', () {
    test('captures a small textual body', () {
      expect(bodyOf('small-json'), '{"ok":true}');
      expect(bodyReadsOf('small-json'), 1);
    });

    test('never reads an oversized body into memory', () {
      expect(bodyReadsOf('huge-json'), 0);
      expect(bodyOf('huge-json'), '(skipped: 50.0 MB application/json)');
    });

    test('never reads a non-text body into memory', () {
      expect(bodyReadsOf('image'), 0);
      expect(bodyOf('image'), '(skipped: 13.0 MB image/jpeg)');
    });

    test('skips an unbounded event stream, which carries no length header', () {
      expect(bodyReadsOf('event-stream'), 0);
      expect(bodyOf('event-stream'), contains('text/event-stream'));
    });

    test('still captures textual responses with no content-length', () {
      expect(bodyOf('html-no-length'), '<html></html>');
    });

    test('truncates a long-but-capturable body to MAX_BODY', () {
      expect(bodyOf('long-text').length, 8192);
    });
  });

  group('XHR hook', () {
    test('captures a small textual body', () {
      expect(bodyOf('xhr-json'), '{"ok":true}');
    });

    test('never reads an oversized body into memory', () {
      expect(bodyReadsOf('xhr-huge'), 0);
      expect(bodyOf('xhr-huge'), contains('skipped'));
    });

    test('never reads a non-text body into memory', () {
      expect(bodyReadsOf('xhr-image'), 0);
      expect(bodyOf('xhr-image'), '(skipped: 2.0 KB image/png)');
    });

    test('skips a non-text responseType without touching responseText', () {
      expect(bodyReadsOf('xhr-arraybuffer'), 0);
    });
  });
}
