import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'debug_drawer.dart';
import 'escape_hatch.dart';
import 'runtime_config.dart';
import 'webview_page.dart';

class PakeApp extends StatefulWidget {
  const PakeApp({super.key, required this.config, this.logsDir});

  final RuntimeConfig config;

  /// `logger_utils` 的日志落盘目录，由 `main.dart` 用 `path_provider` 算出
  /// 来往下传，最终交给 `DebugDrawer` 里的 `LogPage`。
  final String? logsDir;

  @override
  State<PakeApp> createState() => _PakeAppState();
}

class _PakeAppState extends State<PakeApp> {
  final _webViewKey = GlobalKey<WebViewPageState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _openSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => DebugDrawer(
          config: widget.config,
          logsDir: widget.logsDir,
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
      home: Stack(
        children: [
          WebViewPage(
            key: _webViewKey,
            config: widget.config,
            onOpenSettings: _openSettings,
          ),
          EscapeHatch(onTriggered: _openSettings),
        ],
      ),
    );
  }
}
