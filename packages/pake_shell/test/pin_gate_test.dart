import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/lock/pin_gate.dart';
import 'package:pake_shell/src/runtime_config.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
);

void main() {
  late RuntimeConfig config;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // get_storage 在真机上靠 path_provider 找文档目录；单元测试没有原生
    // 插件通道，这里喂一个假实现，指向临时目录。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_shell_test').path,
        );

    await GetStorage.init();
    await GetStorage().erase();
    config = RuntimeConfig.fromBuildTime(_buildTime);
  });

  Future<void> pump(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PinGate(
          config: config,
          timeout: timeout,
          child: const Text('the web page'),
        ),
      ),
    );
  }

  Future<void> leaveAndReturn(WidgetTester tester, Duration away) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // 必须用 runAsync：testWidgets 默认跑在 FakeAsync 里，`tester.pump(d)`
    // 只推进假时钟，而 PinGate 算的是 `DateTime.now()` 的真实时间差——
    // 假时钟推得再多，那个差值也是 0。runAsync 里时间是真的会走的。
    await tester.runAsync(() => Future<void>.delayed(away));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('lets the page through when the lock is off', (tester) async {
    await pump(tester);

    expect(find.text('the web page'), findsOneWidget);
  });

  testWidgets('locks on a cold start when the lock is on', (tester) async {
    config
      ..appLockEnabled = true
      ..pinCode = 1234;

    await pump(tester);

    expect(find.text('the web page'), findsNothing);
    expect(find.text('Weibo'), findsOneWidget);
  });

  testWidgets('lets the page through when no pin was ever set', (tester) async {
    // 防砖回归：残缺的存储状态（开关开着但没 PIN）不能把人挡在外面。
    config.appLockEnabled = true;

    await pump(tester);

    expect(find.text('the web page'), findsOneWidget);
  });

  testWidgets('the correct pin reveals the page', (tester) async {
    config
      ..appLockEnabled = true
      ..pinCode = 1234;
    await pump(tester);

    for (final d in '1234'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pump();

    expect(find.text('the web page'), findsOneWidget);
  });

  testWidgets('a short trip to the background does not lock', (tester) async {
    config
      ..appLockEnabled = true
      ..pinCode = 1234;
    await pump(tester, timeout: const Duration(milliseconds: 200));
    for (final d in '1234'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }

    await leaveAndReturn(tester, const Duration(milliseconds: 20));

    expect(find.text('the web page'), findsOneWidget);
  });

  testWidgets('staying away past the timeout locks again', (tester) async {
    config
      ..appLockEnabled = true
      ..pinCode = 1234;
    await pump(tester, timeout: const Duration(milliseconds: 100));
    for (final d in '1234'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }

    await leaveAndReturn(tester, const Duration(milliseconds: 150));

    expect(find.text('the web page'), findsNothing);
  });

  testWidgets(
    'a second resume with no fresh pause does not lock on a stale timestamp',
    (tester) async {
      // 回归用例：_pausedAt 只在 paused 时写、不在 resumed 时清，会让一次
      // 「没超时」的短暂离开留下一个陈旧时间戳。之后哪怕没有新的 paused，
      // 单靠再来一次 resumed（比如下拉通知栏又收起）也能凑够时间差，
      // 把人错误地锁在外面。
      config
        ..appLockEnabled = true
        ..pinCode = 1234;
      await pump(tester, timeout: const Duration(milliseconds: 100));
      for (final d in '1234'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }

      // 短暂离开又回来，没有超时，不该锁。
      await leaveAndReturn(tester, const Duration(milliseconds: 20));
      expect(find.text('the web page'), findsOneWidget);

      // 没有新的 paused——直接等过超时时长，再发一次 resumed。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('the web page'), findsOneWidget);
    },
  );

  testWidgets('enabling the lock after an old pause does not lock on the stale '
      'timestamp', (tester) async {
    // 第二类回归：round 1 把清空 _pausedAt 的代码放在了配置检查之后。
    // 锁关着的时候第一次 resumed 会被前面的 guard 挡住，清空代码根本
    // 没机会跑，陈旧时间戳照样留着。之后哪怕全程在前台把锁打开（没有
    // 任何新的 paused），下一次 resumed 也会拿这个陈旧时间戳去算差，
    // 把人错误地锁在外面。
    await pump(tester, timeout: const Duration(milliseconds: 100));

    // 锁关着的时候进出一次后台——guard 挡住了清空，陈旧时间戳留下。
    await leaveAndReturn(tester, const Duration(milliseconds: 10));
    expect(find.text('the web page'), findsOneWidget);

    // 全程前台：直接在 config 上开锁、设 PIN，没有任何生命周期事件。
    config
      ..appLockEnabled = true
      ..pinCode = 1234;
    await tester.pump();

    // 没有新的 paused——直接等过超时时长，再发一次 resumed。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('the web page'), findsOneWidget);
  });
}
