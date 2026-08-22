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

  group('barStateAfterScroll', () {
    // 栏高固定 48（BottomBar.height），下面的用例都用它。
    ({bool visible, int anchor}) step({
      required int y,
      required int anchor,
      required bool visible,
    }) => barStateAfterScroll(
      y: y,
      anchor: anchor,
      visible: visible,
      barHeight: 48,
    );

    test('stays put below the threshold, and keeps the anchor', () {
      // 锚点不能跟着走——跟着走就永远攒不满 10px，栏再也不会翻转。
      final r = step(y: 108, anchor: 100, visible: true);

      expect(r.visible, isTrue);
      expect(r.anchor, 100);
    });

    test('scrolling down past the threshold hides and re-anchors', () {
      final r = step(y: 111, anchor: 100, visible: true);

      expect(r.visible, isFalse);
      expect(r.anchor, 111);
    });

    test('scrolling up past the threshold shows again', () {
      final r = step(y: 89, anchor: 100, visible: false);

      expect(r.visible, isTrue);
      expect(r.anchor, 89);
    });

    test('reversing direction re-anchors so the next flip is 10px away', () {
      // 下滑藏起来之后立刻回头：锚点已经跟到 111，再上滑 10px 就该出来。
      final hidden = step(y: 111, anchor: 100, visible: true);
      final shown = step(
        y: 101,
        anchor: hidden.anchor,
        visible: hidden.visible,
      );

      expect(shown.visible, isTrue);
    });

    test('the top of the page shows unconditionally', () {
      // 找不到入口时的本能动作是一路滑到顶，这条必须无视阈值和当前状态。
      final r = step(y: 3, anchor: 900, visible: false);

      expect(r.visible, isTrue);
      expect(r.anchor, 3);
    });

    test('just past the bar height is no longer "the top"', () {
      // 48 是边界：小于它一律显示，等于它就回到正常的阈值判定。两边都用
      // 同一次「向下滑了 18px」，差别只在落点跨没跨过 48。
      expect(step(y: 47, anchor: 29, visible: true).visible, isTrue);
      expect(step(y: 48, anchor: 30, visible: true).visible, isFalse);
    });
  });
}
