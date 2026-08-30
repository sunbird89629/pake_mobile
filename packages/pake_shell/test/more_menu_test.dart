import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/more_menu.dart';

void main() {
  group('showMoreMenu', () {
    late MoreAction? result;
    late bool closed;

    Future<void> open(WidgetTester tester) async {
      result = null;
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showMoreMenu(context);
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

    testWidgets('share app returns MoreAction.shareApp and closes', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('more:share-app')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, MoreAction.shareApp);
    });

    testWidgets('dismissing returns null', (tester) async {
      // 点遮罩关掉——调用方靠 null 判断「什么都别做」。
      await open(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });
  });
}
