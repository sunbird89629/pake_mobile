import 'package:flutter/material.dart';

import 'runtime_config.dart';
import 'webview_page.dart';

class PakeApp extends StatefulWidget {
  const PakeApp({super.key, required this.config});

  final RuntimeConfig config;

  @override
  State<PakeApp> createState() => _PakeAppState();
}

class _PakeAppState extends State<PakeApp> {
  final _webViewKey = GlobalKey<WebViewPageState>();

  void _openSettings() {
    // Task 15 会把 DebugDrawer 挂上来。
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.config.buildTime.name,
      debugShowCheckedModeBanner: false,
      home: Stack(
        children: [
          WebViewPage(
            key: _webViewKey,
            config: widget.config,
            onOpenSettings: _openSettings,
          ),
          // Task 14 会在这里加 EscapeHatch。
        ],
      ),
    );
  }
}
