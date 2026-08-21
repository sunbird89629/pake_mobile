import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'debug_drawer.dart';
import 'lock/lock_gate.dart';
import 'runtime_config.dart';
import 'update/pending_update.dart';
import 'update/update_check.dart';
import 'update/update_dialog.dart';
import 'update/update_service.dart';
import 'webview_page.dart';

class PakeApp extends StatefulWidget {
  const PakeApp({
    super.key,
    required this.config,
    this.logsDir,
    this.updateService,
  });

  final RuntimeConfig config;

  /// `logger_utils` 的日志落盘目录，由 `main.dart` 用 `path_provider` 算出
  /// 来往下传，最终交给 `DebugDrawer` 里的 `LogPage`。
  final String? logsDir;

  /// 只为测试注入，生产路径上现造。
  final UpdateService? updateService;

  @override
  State<PakeApp> createState() => _PakeAppState();
}

class _PakeAppState extends State<PakeApp> {
  final _webViewKey = GlobalKey<WebViewPageState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// 锁定状态：`LockGate` 写，`WebViewPage` 读。两者一个在 `builder` 里、
  /// 一个在 `home` 里，够不着彼此，只能由共同的父级持有。
  final _locked = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _pending = PendingUpdate(locked: _locked, onReady: _showUpdate);
    _checkForUpdate();
  }

  @override
  void dispose() {
    _pending.dispose();
    _locked.dispose();
    super.dispose();
  }

  late final PendingUpdate _pending;

  /// iOS 上不自动查：侧载的 IPA 点了链接也装不上（要 AltStore、重签名或
  /// Xcode 重装），弹一个「有新版」只是在告诉用户一件他无能为力的事。
  /// 设置页里的手动检查两端都留着。
  Future<void> _checkForUpdate() async {
    if (Platform.isIOS) return;

    final info = await (widget.updateService ?? UpdateService(widget.config))
        .checkOnLaunch();
    if (info == null || !mounted) return;

    _pending.offer(info);
  }

  void _showUpdate(UpdateInfo info) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    showUpdateDialog(
      context,
      info,
      onDismiss: (version) => widget.config.dismissedUpdateVersion = version,
    );
  }

  void _openSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => DebugDrawer(
          config: widget.config,
          logsDir: widget.logsDir,
          netLog: _webViewKey.currentState!.netLog,
          onReloadRequested: () =>
              _webViewKey.currentState?.reloadWithCurrentSettings(),
          onClearCache: () async {
            await InAppWebViewController.clearAllCache();
            await CookieManager.instance().deleteAllCookies();
            await WebStorageManager.instance().deleteAllData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: widget.config.buildTime.name,
      debugShowCheckedModeBanner: false,
      // 挂 builder 而不是包 home：设置页是 push 出来的路由，包 home 的话
      // 人在设置页里切后台再回来，锁屏会被设置页盖住，等于没锁。
      builder: (context, child) =>
          LockGate(config: widget.config, locked: _locked, child: child!),
      // 曾经在这里叠过一个 EscapeHatch（左上角长按 1.5 秒进设置）。它被
      // 底部胶囊上的 ⚙ 取代了——那块 44×44 的长按识别区正好压在移动站放
      // 汉堡菜单和返回按钮的位置，在那儿长按网页里的链接或图片会打开设置
      // 而不是弹出网页的上下文菜单。
      home: WebViewPage(
        key: _webViewKey,
        config: widget.config,
        onOpenSettings: _openSettings,
        locked: _locked,
      ),
    );
  }
}
