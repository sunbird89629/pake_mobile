import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/lock/lock_screen.dart';
import 'package:pake_shell/src/lock/pattern_code.dart';

import 'support/draw_pattern.dart';

void main() {
  late int unlockCount;

  const correct = [0, 1, 2, 5];

  setUp(() => unlockCount = 0);

  Future<void> pump(WidgetTester tester) async {
    // 默认 800x600 的测试画布放不下 280 的图案盘加上下文案。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          patternHash: hashPattern(correct),
          appName: 'Weibo',
          onUnlocked: () => unlockCount++,
        ),
      ),
    );
  }

  testWidgets('names the app so the user knows what is asking', (tester) async {
    await pump(tester);

    expect(find.text('Weibo'), findsOneWidget);
  });

  testWidgets('the correct pattern unlocks', (tester) async {
    await pump(tester);

    await drawPattern(tester, correct);

    expect(unlockCount, 1);
  });

  testWidgets('a wrong pattern does not unlock', (tester) async {
    await pump(tester);

    await drawPattern(tester, const [6, 7, 8, 5]);

    expect(unlockCount, 0);
    expect(find.text('Wrong pattern'), findsOneWidget);
  });

  testWidgets('the same dots in reverse are a different pattern', (
    tester,
  ) async {
    // 图案是有向的。这条盯住的是 hashPattern 的顺序敏感性没有在 UI 这一层
    // 被抹平。
    await pump(tester);

    await drawPattern(tester, correct.reversed.toList());

    expect(unlockCount, 0);
  });

  testWidgets('starting a new attempt clears the error', (tester) async {
    await pump(tester);
    await drawPattern(tester, const [6, 7, 8, 5]);
    expect(find.text('Wrong pattern'), findsOneWidget);

    await drawPattern(tester, correct);

    expect(unlockCount, 1);
    expect(find.text('Wrong pattern'), findsNothing);
  });
}
