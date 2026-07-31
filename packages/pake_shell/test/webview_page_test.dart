import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/webview_page.dart';

void main() {
  group('scriptsKey', () {
    test('re-reading the same set gives the same key regardless of order', () {
      expect(
        scriptsKey(['hide-ads', 'dark-mode']),
        scriptsKey(['dark-mode', 'hide-ads']),
      );
    });

    test('swapping one id for another changes the key even at equal count', () {
      // 关 A 开 B：数量不变，集合变了——这是 ValueKey(_scripts.length) 会漏掉的场景。
      final before = scriptsKey(['hide-ads', 'dark-mode']);
      final after = scriptsKey(['hide-ads', 'auto-translate']);

      expect(after, isNot(equals(before)));
    });

    test('adding or removing an id changes the key', () {
      final base = scriptsKey(['hide-ads']);
      final withMore = scriptsKey(['hide-ads', 'dark-mode']);

      expect(withMore, isNot(equals(base)));
    });

    test('empty set has a stable key', () {
      expect(scriptsKey(const []), scriptsKey(const []));
    });
  });
}
