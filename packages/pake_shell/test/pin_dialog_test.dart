import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/lock/pin_dialog.dart';

void main() {
  group('validatePin', () {
    test('accepts a 4-digit pin entered twice', () {
      expect(validatePin('1234', '1234'), isNull);
    });

    test('rejects anything that is not 4 digits', () {
      expect(validatePin('123', '123'), isNotNull);
      expect(validatePin('12345', '12345'), isNotNull);
      expect(validatePin('12a4', '12a4'), isNotNull);
      expect(validatePin('', ''), isNotNull);
    });

    test('rejects a leading zero', () {
      // int.parse('0123') == 123——允许 0 开头会让两个看起来不同的 PIN
      // 变成同一个。
      expect(validatePin('0123', '0123'), isNotNull);
    });

    test('rejects a mismatched confirmation', () {
      expect(validatePin('1234', '1235'), isNotNull);
    });
  });

  group('showPinDialog', () {
    Future<void> pump(WidgetTester tester, List<int?> captured) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      captured.add(await showPinDialog(context)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('returns the new pin once both entries agree', (tester) async {
      final captured = <int?>[];
      await pump(tester, captured);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('newPin')), '1234');
      await tester.enterText(find.byKey(const ValueKey('confirmPin')), '1234');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(captured, [1234]);
    });

    testWidgets('keeps the dialog open and explains a bad pin', (tester) async {
      final captured = <int?>[];
      await pump(tester, captured);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('newPin')), '1234');
      await tester.enterText(find.byKey(const ValueKey('confirmPin')), '9999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget, reason: '对话框必须还开着');
      expect(captured, isEmpty);
      expect(
        find.textContaining('match'),
        findsOneWidget,
        reason: '必须说清楚为什么没保存',
      );
    });

    testWidgets('cancelling returns null', (tester) async {
      final captured = <int?>[];
      await pump(tester, captured);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(captured, [null]);
    });
  });
}
