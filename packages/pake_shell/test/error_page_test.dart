import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/error_page.dart';

void main() {
  group('classifyFailure', () {
    test('maps host-lookup and cannot-connect-to-host to offline', () {
      // 真实包的 WebResourceErrorType 里没有 'CONNECT' 这个值——Android/iOS
      // 的"连不上服务器"统一映射到 'CANNOT_CONNECT_TO_HOST'。
      expect(
        classifyFailure(errorType: 'HOST_LOOKUP'),
        LoadFailureKind.offline,
      );
      expect(
        classifyFailure(errorType: 'CANNOT_CONNECT_TO_HOST'),
        LoadFailureKind.offline,
      );
    });

    test('maps 404 to a bad url', () {
      expect(classifyFailure(httpStatus: 404), LoadFailureKind.badUrl);
    });

    test('maps 5xx to a server error, not a bad url', () {
      expect(classifyFailure(httpStatus: 503), LoadFailureKind.serverError);
    });

    test('maps a malformed url to a bad url, not offline', () {
      // 'BAD_URL' 是包里真实存在的值——一个格式错误的 URL 拦不到网络层。
      expect(classifyFailure(errorType: 'BAD_URL'), LoadFailureKind.badUrl);
    });
  });

  group('ErrorPage', () {
    Future<void> pump(WidgetTester tester, LoadFailureKind kind) =>
        tester.pumpWidget(
          MaterialApp(
            home: ErrorPage(
              kind: kind,
              url: 'https://m.weibo.cn',
              onRetry: () {},
              onOpenSettings: () {},
            ),
          ),
        );

    testWidgets('offline tells the user to wait, and offers no url edit', (
      tester,
    ) async {
      await pump(tester, LoadFailureKind.offline);

      expect(find.textContaining('network'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('bad url guides the user into settings', (tester) async {
      await pump(tester, LoadFailureKind.badUrl);

      expect(find.text('Open settings'), findsOneWidget);
      expect(find.textContaining('https://m.weibo.cn'), findsOneWidget);
    });

    testWidgets('every failure kind offers an escape into settings', (
      tester,
    ) async {
      // 白屏被困是这类 app 最常见的失效方式——每种错误都必须有出口。
      for (final kind in LoadFailureKind.values) {
        await pump(tester, kind);
        expect(find.text('Open settings'), findsOneWidget, reason: '$kind');
      }
    });

    testWidgets('retry fires the callback', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ErrorPage(
            kind: LoadFailureKind.offline,
            url: 'https://m.weibo.cn',
            onRetry: () => retried = true,
            onOpenSettings: () {},
          ),
        ),
      );

      await tester.tap(find.text('Retry'));

      expect(retried, isTrue);
    });
  });
}
