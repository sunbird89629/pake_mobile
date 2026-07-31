import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/debug_drawer.dart';
import 'package:pake_shell/src/net/net_log.dart';
import 'package:pake_shell/src/runtime_config.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  injectScripts: ['hide-ads.js', 'fix-video.js'],
);

void main() {
  late RuntimeConfig config;
  late int reloadCount;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // get_storage 在真机上靠 path_provider 找文档目录；单元测试没有原生插件
    // 通道，这里喂一个假实现，指向临时目录，跟被测逻辑本身无关。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_shell_test').path,
        );

    await GetStorage.init();
    await GetStorage().erase();
    config = RuntimeConfig.fromBuildTime(_buildTime);
    reloadCount = 0;
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: DebugDrawer(
        config: config,
        onReloadRequested: () => reloadCount++,
        onClearCache: () async {},
        netLog: NetLog(),
      ),
    ),
  );

  group('uaPresetOrder', () {
    test('puts the current UA first so the sheet preselects it', () {
      // DebugSelectSheet 没有 initialIndex，_selectedIndex 恒从 0 起。
      final order = uaPresetOrder(UserAgentPresets.all['Desktop']!);

      expect(order.first, 'Desktop');
    });

    test('puts Default first when no UA override is set', () {
      expect(uaPresetOrder('').first, 'Default');
    });

    test('puts Custom first when the UA matches no preset', () {
      final order = uaPresetOrder('my-weird-ua/1.0');

      expect(order.first, 'Custom…');
    });

    test('always offers every preset plus Custom exactly once', () {
      final order = uaPresetOrder('');

      expect(order.toSet().length, order.length);
      expect(order, containsAll(UserAgentPresets.all.keys));
      expect(order, contains('Custom…'));
    });
  });

  group('DebugDrawer', () {
    testWidgets('lists one switch per inject script', (tester) async {
      await pump(tester);

      expect(find.text('hide-ads.js'), findsOneWidget);
      expect(find.text('fix-video.js'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(2));
    });

    testWidgets('every script starts enabled', (tester) async {
      await pump(tester);

      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.every((s) => s.value), isTrue);
    });

    testWidgets('toggling a script persists it and triggers a reload', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(config.enabledScripts, isNot(contains('hide-ads.js')));
      expect(reloadCount, 1, reason: 'scripts only take effect on next load');
    });

    testWidgets('states plainly that toggles apply on reload', (tester) async {
      // 不写清楚，用户会以为开关坏了。
      await pump(tester);

      expect(find.textContaining('reload'), findsWidgets);
    });

    testWidgets('reset restores the build-time url and reloads', (
      tester,
    ) async {
      config.url = 'https://changed.example.com';
      await pump(tester);

      // 加了「View requests」入口后，Reset 这一项被挤出默认视口的懒加载
      // 缓存区，得先滚到可见再点。
      await tester.scrollUntilVisible(
        find.text('Reset to build defaults'),
        200,
      );
      await tester.tap(find.text('Reset to build defaults'));
      await tester.pumpAndSettle();

      expect(config.url, 'https://m.weibo.cn');
      expect(reloadCount, 1);
    });

    testWidgets('shows the current url so the user knows what is loaded', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('https://m.weibo.cn'), findsWidgets);
    });
  });
}
