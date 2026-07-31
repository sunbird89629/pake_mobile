import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/escape_hatch.dart';

void main() {
  Future<int> pumpAndHold(WidgetTester tester, Duration hold) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
            EscapeHatch(onTriggered: () => count++),
          ],
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(10, 10));
    await tester.pump(hold);
    await gesture.up();
    await tester.pumpAndSettle();
    return count;
  }

  testWidgets('a 1.5s long press triggers it', (tester) async {
    expect(await pumpAndHold(tester, const Duration(milliseconds: 1600)), 1);
  });

  testWidgets('a normal 500ms long press does NOT trigger it', (tester) async {
    // 用默认的 500ms 就会误触——这正是要自定义 duration 的原因。
    expect(await pumpAndHold(tester, const Duration(milliseconds: 600)), 0);
  });

  testWidgets('a tap does not trigger it', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: [EscapeHatch(onTriggered: () => count++)]),
      ),
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(count, 0);
  });

  testWidgets('a short tap in the corner reaches the content behind it', (
    tester,
  ) async {
    // opaque 会在这里吞掉命中测试，底下的 WebView 收不到任何短按——
    // 而移动站点的汉堡菜单和返回按钮就在这 44×44 里。
    var behindTaps = 0;
    var triggered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              onTap: () => behindTaps++,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox.expand(),
              ),
            ),
            EscapeHatch(onTriggered: () => triggered++),
          ],
        ),
      ),
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(behindTaps, 1, reason: 'the site\'s own top-left button must work');
    expect(triggered, 0);
  });

  testWidgets('the long press still wins over content behind it', (
    tester,
  ) async {
    // translucent 让底下的目标也进了手势竞技场——必须确认 1.5s 长按仍然
    // 识别得到，且不会退化成底下那个 onTap。
    var behindTaps = 0;
    var triggered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              onTap: () => behindTaps++,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox.expand(),
              ),
            ),
            EscapeHatch(onTriggered: () => triggered++),
          ],
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(triggered, 1);
    expect(behindTaps, 0, reason: 'a long press must not double as a tap');
  });

  testWidgets('it occupies a 44x44 area pinned to the top-left corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: [EscapeHatch(onTriggered: () {})]),
      ),
    );

    final box = tester.getRect(find.byType(EscapeHatch));

    expect(box.width, 44);
    expect(box.height, 44);
    expect(box.topLeft, Offset.zero);
  });

  testWidgets('a press outside the corner does not trigger it', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: [EscapeHatch(onTriggered: () => count++)]),
      ),
    );

    final gesture = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(count, 0);
  });
}
