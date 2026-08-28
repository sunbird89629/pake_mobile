import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/lock/pattern_code.dart';
import 'package:pake_shell/src/lock/pattern_page.dart';

import 'support/draw_pattern.dart';

void main() {
  late String? result;
  late bool closed;

  const a = [0, 1, 2, 5];
  const b = [6, 7, 8, 5];

  setUp(() {
    result = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPatternPage(context);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('two matching patterns return the hash, never the pattern', (
    tester,
  ) async {
    await open(tester);

    await drawPattern(tester, a);
    await drawPattern(tester, a);
    await tester.pumpAndSettle();

    expect(result, hashPattern(a));
    expect(result, isNot(contains('0-1-2-5')));
  });

  testWidgets('it asks for the pattern twice', (tester) async {
    await open(tester);
    expect(find.text('Draw a new pattern'), findsOneWidget);

    await drawPattern(tester, a);

    expect(find.text('Draw it again'), findsOneWidget);
    expect(closed, isFalse, reason: '一笔画完不该直接就存了');
  });

  testWidgets('a mismatch sends the user back to the first step', (
    tester,
  ) async {
    // 退回第一步而不是只让人重画第二笔——留着一笔的话，人分不清自己在画第几笔。
    await open(tester);

    await drawPattern(tester, a);
    await drawPattern(tester, b);

    expect(find.text('Draw a new pattern'), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('a too-short pattern is rejected on the first draw', (
    tester,
  ) async {
    // 长度在第一笔就卡掉，不能等人画完第二笔才说太短。
    await open(tester);

    await drawPattern(tester, const [0, 1, 2]);

    expect(find.text('Draw a new pattern'), findsOneWidget);
    expect(find.textContaining('at least'), findsOneWidget);
  });

  testWidgets('the same dots drawn in reverse do not confirm', (tester) async {
    await open(tester);

    await drawPattern(tester, a);
    await drawPattern(tester, a.reversed.toList());

    expect(closed, isFalse);
    expect(find.text('Draw a new pattern'), findsOneWidget);
  });

  testWidgets('backing out returns null', (tester) async {
    // 整页之后「取消」就是返回箭头，不再是页面里的一个按钮。
    await open(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('opens as a route, not a dialog', (tester) async {
    // 换成整页的理由：对话框里那块网格只有 260 见方，比锁屏上真正解锁用的
    // 那块还小，手感对不上。
    await open(tester);

    expect(find.byType(Dialog), findsNothing);
    expect(tester.getSize(find.byType(PatternLock)), const Size(280, 280));
  });
}
