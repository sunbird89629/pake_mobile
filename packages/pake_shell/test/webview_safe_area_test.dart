import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/runtime_config.dart';
import 'package:pake_shell/src/webview_page.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
);

const _webViewKey = Key('fake-inappwebview');

/// `InAppWebView` 的构造函数断言 `InAppWebViewPlatform.instance != null`，
/// 单测里没有原生实现——插件自己的报错信息就指明了这条路：喂一个测试实现。
/// 只需要它在树里占住 `InAppWebView` 那个位置，好让布局断言拿得到矩形。
class _FakeWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeWebViewWidget extends PlatformInAppWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: _webViewKey);

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      controller as T;

  @override
  void dispose() {}
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_shell_test').path,
        );
    await GetStorage.init();
    await GetStorage().erase();
    InAppWebViewPlatform.instance = _FakeWebViewPlatform();
  });

  testWidgets('web content is inset out from under the status bar and notch', (
    tester,
  ) async {
    // 不包 SafeArea 时网页从 y=0 开始画，站点自己的顶部导航就压在时钟
    // 底下。ErrorPage 一直是包着的——这是那条不对称。
    const statusBar = 47.0;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: statusBar)),
        child: MaterialApp(
          home: WebViewPage(
            config: RuntimeConfig.fromBuildTime(_buildTime),
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(_webViewKey)).dy,
      statusBar,
      reason: 'the page must start below the status bar',
    );
  });
}
