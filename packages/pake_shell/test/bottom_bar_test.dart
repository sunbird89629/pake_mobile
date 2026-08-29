import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/bottom_bar.dart';

void main() {
  group('BottomBar', () {
    late List<String> taps;

    setUp(() => taps = []);

    Future<void> pump(
      WidgetTester tester, {
      bool visible = true,
      bool canGoBack = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomBar(
            visible: visible,
            canGoBack: canGoBack,
            onBack: () => taps.add('back'),
            onReload: () => taps.add('reload'),
            onOpenSettings: () => taps.add('settings'),
            onMore: () => taps.add('more'),
          ),
        ),
      ),
    );

    testWidgets('each button calls its own callback', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.tap(find.byIcon(Icons.more_horiz));

      expect(taps, ['back', 'reload', 'settings', 'more']);
    });

    testWidgets('back is disabled with no history', (tester) async {
      await pump(tester, canGoBack: false);

      await tester.tap(find.byIcon(Icons.arrow_back));

      expect(taps, isEmpty);
    });

    testWidgets('the other three stay live with no history', (tester) async {
      // 只有后退跟历史有关。刷新、设置、更多任何时候都必须能点——设置尤其：
      // 删掉 EscapeHatch 之后它是仅剩的设置入口。
      await pump(tester, canGoBack: false);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.tap(find.byIcon(Icons.more_horiz));

      expect(taps, ['reload', 'settings', 'more']);
    });

    testWidgets('hidden bar swallows no taps', (tester) async {
      await pump(tester, visible: false);
      await tester.pumpAndSettle();

      // 隐藏时整条栏被 IgnorePointer 关掉：它滑出屏幕后盖住的是网页的可点
      // 区域，不能再吃事件。warnIfMissed 关掉是因为命中必然落空——那正是
      // 这里要断言的。
      await tester.tap(
        find.byIcon(Icons.settings_outlined),
        warnIfMissed: false,
      );

      expect(taps, isEmpty);
    });

    testWidgets('visibility drives the slide offset', (tester) async {
      await pump(tester, visible: true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero,
      );

      await pump(tester, visible: false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        const Offset(0, 2),
      );
    });

    testWidgets('every tap target clears the 44px floor', (tester) async {
      // 栏宽是钉死的（274），四个格子必须塞得进去；同时不能为了塞进去
      // 把格子缩到手指点不准。44 是移动端触控下限，不是审美问题。
      await pump(tester);

      for (final icon in [
        Icons.arrow_back,
        Icons.refresh,
        Icons.settings_outlined,
        Icons.more_horiz,
      ]) {
        final size = tester.getSize(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(IconButton),
          ),
        );
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the bar still fits the narrowest phone', (tester) async {
      // 加第四个按钮把栏从 208 撑到了 274。360dp 是主流窄屏（Pixel 竖屏就是
      // 360），栏在那上面必须还是一块浮着的胶囊，而不是顶满两边的一条杠。
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester);

      final width = tester.getSize(find.byType(BackdropFilter)).width;
      expect(width, lessThanOrEqualTo(360 - 32));
    });
  });
}
