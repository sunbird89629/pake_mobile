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
          ),
        ),
      ),
    );

    testWidgets('each button calls its own callback', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.settings_outlined));

      expect(taps, ['back', 'reload', 'settings']);
    });

    testWidgets('back is disabled with no history', (tester) async {
      await pump(tester, canGoBack: false);

      await tester.tap(find.byIcon(Icons.arrow_back));

      expect(taps, isEmpty);
    });

    testWidgets('the other two stay live with no history', (tester) async {
      // 只有后退跟历史有关。刷新和设置任何时候都必须能点——设置尤其：
      // 删掉 EscapeHatch 之后它是仅剩的设置入口。
      await pump(tester, canGoBack: false);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.settings_outlined));

      expect(taps, ['reload', 'settings']);
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
      // 栏宽是钉死的（208），三个格子必须塞得进去；同时不能为了塞进去
      // 把格子缩到手指点不准。44 是移动端触控下限，不是审美问题。
      await pump(tester);

      for (final icon in [
        Icons.arrow_back,
        Icons.refresh,
        Icons.settings_outlined,
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
  });
}
