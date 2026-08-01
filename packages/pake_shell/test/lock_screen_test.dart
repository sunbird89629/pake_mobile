import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/lock/lock_screen.dart';

void main() {
  late int unlockCount;

  setUp(() => unlockCount = 0);

  Future<void> pump(WidgetTester tester) async {
    // 默认的 800x600 测试画布放不下整块数字键盘，点不到的按钮 tap 会失败。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          pinCode: 1234,
          appName: 'Weibo',
          onUnlocked: () => unlockCount++,
        ),
      ),
    );
  }

  Future<void> enter(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
  }

  testWidgets('names the app so the user knows what is asking', (tester) async {
    await pump(tester);

    expect(find.text('Weibo'), findsOneWidget);
  });

  testWidgets('the correct pin unlocks', (tester) async {
    await pump(tester);

    await enter(tester, '1234');

    expect(unlockCount, 1);
  });

  testWidgets('a wrong pin does not unlock', (tester) async {
    await pump(tester);

    await enter(tester, '9999');
    await tester.pumpAndSettle();

    expect(unlockCount, 0);
  });
}
