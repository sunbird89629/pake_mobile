import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/net/net_log.dart';
import 'package:pake_shell/src/net/net_record.dart';

NetRecord _rec(String url, {int status = 200}) => NetRecord(
  url: url,
  method: 'GET',
  status: status,
  durationMs: 12,
  at: DateTime(2026, 7, 30),
);

void main() {
  group('NetLog', () {
    test('keeps the most recent records first', () {
      final log = NetLog()
        ..add(_rec('https://a.com'))
        ..add(_rec('https://b.com'));

      expect(log.records.first.url, 'https://b.com');
    });

    test('drops the oldest record once capacity is exceeded', () {
      final log = NetLog(capacity: 2)
        ..add(_rec('https://1.com'))
        ..add(_rec('https://2.com'))
        ..add(_rec('https://3.com'));

      expect(log.records.length, 2);
      expect(log.records.map((r) => r.url), ['https://3.com', 'https://2.com']);
    });

    test('notifies listeners on add', () async {
      final log = NetLog();
      final future = log.changes.first;

      log.add(_rec('https://a.com'));

      await expectLater(future, completes);
    });

    test('clear empties the buffer', () {
      final log = NetLog()..add(_rec('https://a.com'));

      log.clear();

      expect(log.records, isEmpty);
    });
  });

  group('NetRecord.toCurl', () {
    test('emits a runnable curl command', () {
      final curl = NetRecord(
        url: 'https://api.example.com/v1/items?q=1',
        method: 'POST',
        status: 201,
        durationMs: 40,
        at: DateTime(2026, 7, 30),
        requestHeaders: const {'Content-Type': 'application/json'},
        requestBody: '{"a":1}',
      ).toCurl();

      expect(
        curl,
        startsWith("curl -X POST 'https://api.example.com/v1/items?q=1'"),
      );
      expect(curl, contains("-H 'Content-Type: application/json'"));
      expect(curl, contains("""--data-raw '{"a":1}'"""));
    });

    test('escapes single quotes so the command stays valid', () {
      final curl = NetRecord(
        url: 'https://a.com',
        method: 'POST',
        status: 200,
        durationMs: 1,
        at: DateTime(2026, 7, 30),
        requestBody: "it's",
      ).toCurl();

      expect(curl, contains(r"'it'\''s'"));
    });

    test('omits the data flag for GET requests without a body', () {
      expect(_rec('https://a.com').toCurl(), isNot(contains('--data-raw')));
    });

    test('notes that headers/body were not captured when both are missing, '
        'on its own line', () {
      // net_hook.js 从不抓请求头/体——不说明的话，导出的命令看着像一次
      // 忠实回放，其实一个请求头都没有。注释必须在自己的一行：macOS 默认
      // 交互式 zsh 没开 INTERACTIVE_COMMENTS，同一行里的 `#` 不会被当
      // 注释，粘贴执行会报错。
      final curl = _rec('https://a.com').toCurl();
      final lines = curl.split('\n');

      expect(lines, hasLength(2));
      expect(lines[0], isNot(contains('#')));
      expect(lines[1], '# note: request headers/body were not captured');
    });

    test('says nothing when headers or body were captured', () {
      final curl = NetRecord(
        url: 'https://api.example.com/v1/items?q=1',
        method: 'POST',
        status: 201,
        durationMs: 40,
        at: DateTime(2026, 7, 30),
        requestHeaders: const {'Content-Type': 'application/json'},
        requestBody: '{"a":1}',
      ).toCurl();

      expect(curl, isNot(contains('# note:')));
    });
  });

  group('NetRecord.fromHandlerJson', () {
    test('parses what net_hook.js posts over callHandler', () {
      final r = NetRecord.fromHandlerJson({
        'url': 'https://api.example.com/x',
        'method': 'GET',
        'status': 200,
        'ms': 33,
        'body': '{"ok":true}',
      });

      expect(r.url, 'https://api.example.com/x');
      expect(r.durationMs, 33);
      expect(r.body, '{"ok":true}');
      expect(r.source, NetSource.js);
    });

    test('survives a malformed payload without throwing', () {
      final r = NetRecord.fromHandlerJson({'url': 12345, 'status': 'nope'});

      expect(r.url, isNotEmpty);
      expect(r.status, -1);
    });
  });
}
