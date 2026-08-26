import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/debug_drawer.dart';
import 'package:pake_shell/src/lock/pattern_code.dart';
import 'package:pake_shell/src/net/net_log.dart';
import 'package:pake_shell/src/runtime_config.dart';
import 'package:pake_shell/src/update/update_service.dart';

import 'support/draw_pattern.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  injectScripts: ['hide-ads.js', 'fix-video.js'],
);

/// 设置用的图案，以及改成的另一个。
const _first = [0, 1, 2, 5];
const _second = [6, 7, 8, 5];

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

  Future<void> pump(
    WidgetTester tester, {
    UpdateService? updateService,
    bool showDebugItems = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: DebugDrawer(
        config: config,
        onReloadRequested: () => reloadCount++,
        onClearCache: () async {},
        netLog: NetLog(),
        updateService: updateService,
        showDebugItems: showDebugItems,
      ),
    ),
  );

  /// 点到「Check for updates」那一行——它在列表底部，得先滚过去。
  Future<void> tapCheckForUpdates(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkForUpdates')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('checkForUpdates')));
    await tester.pumpAndSettle();
  }

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
    testWidgets('lists one switch per inject script, keyed by script id', (
      tester,
    ) async {
      await pump(tester);

      // id，不是 pake.json 里的原始路径：开关写进 enabledScripts 的必须是
      // `assets/scripts/index.json` 里那个 id，否则 WebViewPage 读不到。
      expect(find.text('hide-ads'), findsOneWidget);
      expect(find.text('fix-video'), findsOneWidget);
      // 按 key 数，而不是数所有 SwitchListTile——设置页还有别的开关
      // （比如 Capture network），那个计数会跟着无关改动一起漂。
      expect(
        find.byWidgetPredicate(
          (w) => w is SwitchListTile && w.key.toString().contains('script:'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('every script starts enabled', (tester) async {
      await pump(tester);

      // 按 key 过滤到脚本开关——设置页还有别的开关（比如 App lock），
      // 那些默认值跟脚本无关，混进来断言会跟着无关改动一起漂。
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .where((s) => s.key.toString().contains('script:'));
      expect(switches.every((s) => s.value), isTrue);
    });

    testWidgets('toggling a script persists it and triggers a reload', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(config.enabledScripts, isNot(contains('hide-ads')));
      expect(
        config.enabledScripts,
        contains('fix-video'),
        reason:
            'turning one script off must leave the others on — and the set '
            'that survives has to be ids, or nothing matches index.json',
      );
      expect(reloadCount, 1, reason: 'scripts only take effect on next load');
    });

    testWidgets('offers a switch that turns network capture off', (
      tester,
    ) async {
      // 抓包 hook 曾经是唯一没有开关的注入脚本。
      await pump(tester);

      await tester.scrollUntilVisible(find.text('Capture network'), 200);
      await tester.tap(find.text('Capture network'));
      await tester.pumpAndSettle();

      expect(config.captureNetwork, isFalse);
      expect(reloadCount, 1, reason: 'scripts only take effect on next load');
    });

    testWidgets('drops the whole group when no script is bundled', (
      tester,
    ) async {
      // 只剩一个标题和「toggling a script reloads the page」的说明、底下一个
      // 开关都没有，是在讲一件这个 app 里不存在的事。正式包里藏掉 URL / UA
      // 之后它还正好落在页面顶部——真机上一眼就看见了。
      config = RuntimeConfig.fromBuildTime(
        const PakeConfig(
          name: 'Weibo',
          url: 'https://m.weibo.cn',
          bundleId: 'com.pake.weibo',
        ),
      );
      await pump(tester);

      expect(find.text('Inject scripts'), findsNothing);
      expect(find.textContaining('take effect'), findsNothing);
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

  group('release build', () {
    /// 直接读 `ListView` 的 children，而不是 `find.text`——列表底部的项在默认
    /// 视口下压根没被 build，用 find 断言「找不到」会把「没渲染」当成「被藏了」，
    /// 一路假通过。这里问的是「在不在这份列表里」。
    List<Widget> childrenOf(WidgetTester tester) =>
        (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                as SliverChildListDelegate)
            .children;

    List<String> titlesOf(WidgetTester tester) => childrenOf(tester)
        .map(
          (w) => w is ListTile
              ? w.title
              : w is SwitchListTile
              ? w.title
              : null,
        )
        .whereType<Text>()
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    testWidgets('drops the developer-only items', (tester) async {
      await pump(tester, showDebugItems: false);

      // URL 和 User agent 是最危险的两个：普通用户改错了，这个壳就变成一个
      // 打不开的空白页，而唯一的退路（Reset）也在这一组里。
      expect(
        titlesOf(tester),
        isNot(
          anyElement(
            isIn([
              'URL',
              'User agent',
              'Capture network',
              'View logs',
              'View requests',
              'Reset to build defaults',
            ]),
          ),
        ),
      );
    });

    testWidgets('keeps everything a normal user needs', (tester) async {
      await pump(tester, showDebugItems: false);

      expect(
        titlesOf(tester),
        containsAll([
          // 注入脚本留着：`hide-ads` 这类开关对用户是实打实的功能，不是调试项。
          'hide-ads',
          'App lock',
          'Version',
          'Check for updates',
          'Clear cache & cookies',
        ]),
      );
    });

    /// 每个调试项都是连着一条 Divider 一起藏的，藏错了就会在列表头尾留下一条
    /// 悬空的横线——不算 bug，但一眼就丑。
    testWidgets('leaves no dangling divider at either end', (tester) async {
      await pump(tester, showDebugItems: false);

      expect(childrenOf(tester).first, isNot(isA<Divider>()));
      expect(childrenOf(tester).last, isNot(isA<Divider>()));
    });

    testWidgets('shows them again when the flag is left to the build mode', (
      tester,
    ) async {
      // 不传参数 = 用 kShowDebugSettings，而测试永远跑在 debug 模式下。
      await tester.pumpWidget(
        MaterialApp(
          home: DebugDrawer(
            config: config,
            onReloadRequested: () => reloadCount++,
            onClearCache: () async {},
            netLog: NetLog(),
          ),
        ),
      );

      expect(find.text('URL'), findsOneWidget);
    });
  });

  group('app lock', () {
    testWidgets('is off and offers no pin entry until turned on', (
      tester,
    ) async {
      await pump(tester);

      final sw = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('appLock')),
      );
      expect(sw.value, isFalse);
      expect(find.byKey(const ValueKey('changePattern')), findsNothing);
    });

    testWidgets('turning it on asks for a pattern and persists both', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('appLock')));
      await tester.pumpAndSettle();
      // 画两遍：第一遍记下，第二遍确认。
      await drawPattern(tester, _first);
      await drawPattern(tester, _first);

      expect(config.appLockEnabled, isTrue);
      expect(config.patternHash, hashPattern(_first));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('changePattern')),
        200,
      );
      expect(find.byKey(const ValueKey('changePattern')), findsOneWidget);
    });

    testWidgets('cancelling the pattern dialog leaves the lock off', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('appLock')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(config.appLockEnabled, isFalse);
      expect(config.patternHash, isNull);
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('appLock')),
      );
      expect(sw.value, isFalse, reason: '开关必须弹回去');
    });

    testWidgets('turning it off clears the pattern', (tester) async {
      config
        ..appLockEnabled = true
        ..patternHash = hashPattern(_first);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('appLock')));
      await tester.pumpAndSettle();

      expect(config.appLockEnabled, isFalse);
      expect(config.patternHash, isNull);
    });

    testWidgets('changing the pattern keeps the lock on', (tester) async {
      config
        ..appLockEnabled = true
        ..patternHash = hashPattern(_first);
      await pump(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('changePattern')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('changePattern')));
      await tester.pumpAndSettle();
      await drawPattern(tester, _second);
      await drawPattern(tester, _second);

      expect(config.appLockEnabled, isTrue);
      expect(config.patternHash, hashPattern(_second));
    });
  });

  group('updates', () {
    UpdateService service(Fetcher fetch) => UpdateService(config, fetch: fetch);

    testWidgets('shows the installed version', (tester) async {
      await pump(tester);
      // 列表是懒构建的，那一行在屏幕外，得先滚过去才存在。
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkForUpdates')),
        200,
      );

      expect(find.text(_buildTime.version), findsOneWidget);
    });

    // 手动路径必须有确定答复——自动路径的静默在这里是缺陷不是特性。
    testWidgets('says so when there is nothing newer', (tester) async {
      await pump(tester, updateService: service((_) async => '[]'));
      await tapCheckForUpdates(tester);

      expect(find.textContaining('Already on the latest'), findsOneWidget);
    });

    testWidgets('surfaces a newer version with a download action', (
      tester,
    ) async {
      await pump(
        tester,
        updateService: service(
          (_) async => jsonEncode([
            {
              'tag_name': 'weibo-v2.0.0',
              'draft': false,
              'prerelease': false,
              'assets': [
                {
                  'name': 'app.apk',
                  'browser_download_url': 'https://dl/app.apk',
                },
              ],
            },
          ]),
        ),
      );
      await tapCheckForUpdates(tester);

      expect(find.text('Version 2.0.0 is available'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('reports the failure instead of swallowing it', (tester) async {
      await pump(
        tester,
        updateService: service(
          (_) async => throw const SocketException('nope'),
        ),
      );
      await tapCheckForUpdates(tester);

      expect(find.textContaining('Check failed'), findsOneWidget);
    });
  });
}
