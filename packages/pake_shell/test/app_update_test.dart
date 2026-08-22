import 'dart:convert';
import 'dart:io';

import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/lock/lock_gate.dart';
import 'package:pake_shell/src/lock/pattern_code.dart';
import 'package:pake_shell/src/runtime_config.dart';
import 'package:pake_shell/src/update/pending_update.dart';
import 'package:pake_shell/src/update/update_check.dart';
import 'package:pake_shell/src/update/update_dialog.dart';
import 'package:pake_shell/src/update/update_service.dart';

import 'support/draw_pattern.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
);

const _correct = [0, 1, 2, 5];

final _body = jsonEncode([
  {
    'tag_name': 'weibo-v1.2.0',
    'draft': false,
    'prerelease': false,
    'html_url': 'https://page',
    'assets': [
      {
        'name': 'app-arm64-v8a-release.apk',
        'browser_download_url': 'https://dl/app.apk',
      },
    ],
  },
]);

/// `PakeApp` 的骨架，只把 `WebViewPage` 换成一段文字。
///
/// 不直接 pump `PakeApp`：它挂着 `flutter_inappwebview`，widget test 里
/// `InAppWebViewPlatform.instance` 是 null，一 build 就断言失败。**这就是
/// 「更新提示要等锁屏让路」这条从来没被自动化覆盖过的原因**——`PendingUpdate`
/// 的单元测试只测到它自己，测不到它跟 `LockGate`、`showDialog`、
/// `navigatorKey` 拼起来之后还成不成立，而真机上出问题的正是这一层。
///
/// 这份骨架必须跟 `app.dart` 的结构逐字对齐：navigatorKey 挂 MaterialApp、
/// LockGate 挂 builder（在 navigator 之上）、检查在 initState 里发起。
/// 那边改了结构这里不跟，这条测试就会变成自欺欺人。
class _Shell extends StatefulWidget {
  const _Shell({required this.config, required this.service});

  final RuntimeConfig config;
  final UpdateService service;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _locked = ValueNotifier<bool>(false);
  late final PendingUpdate _pending;

  @override
  void initState() {
    super.initState();
    _pending = PendingUpdate(locked: _locked, onReady: _showUpdate);
    _check();
  }

  @override
  void dispose() {
    _pending.dispose();
    _locked.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final info = await widget.service.checkOnLaunch();
    if (info == null || !mounted) return;
    _pending.offer(info);
  }

  void _showUpdate(UpdateInfo info) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showUpdateDialog(
      context,
      info,
      onDismiss: (v) => widget.config.dismissedUpdateVersion = v,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    debugShowCheckedModeBanner: false,
    builder: (context, child) =>
        LockGate(config: widget.config, locked: _locked, child: child!),
    home: const Scaffold(body: Text('the web page')),
  );
}

void main() {
  late RuntimeConfig config;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_shell_test').path,
        );
    await GetStorage.init();
    config = RuntimeConfig.fromBuildTime(_buildTime)..reset();
  });

  Widget shell({Duration latency = Duration.zero}) => _Shell(
    config: config,
    service: UpdateService(
      config,
      fetch: (uri) => Future.delayed(latency, () => _body),
    ),
  );

  testWidgets('with no lock, a found update shows on launch', (tester) async {
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.text('Update available: 1.2.0'), findsOneWidget);
  });

  // 真机上锁屏先起来、网络后回来。用 latency 把这个顺序钉死：不给延迟的话
  // 假 fetch 在第一帧之前就完成了，`locked` 还是 false，走的是上面那条
  // 「没锁」的路径，等于什么都没测到。
  testWidgets('an update found behind the lock screen shows after unlocking', (
    tester,
  ) async {
    config
      ..appLockEnabled = true
      ..patternHash = hashPattern(_correct);

    await tester.pumpWidget(shell(latency: const Duration(seconds: 1)));
    await tester.pump();

    expect(find.byType(PatternLock), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text('Update available: 1.2.0'),
      findsNothing,
      reason: '锁着的时候弹出来，就是白弹掉一次额度',
    );

    await drawPattern(tester, _correct);

    expect(find.text('Update available: 1.2.0'), findsOneWidget);
  });
}
