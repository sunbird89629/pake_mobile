import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger_utils/logger_utils.dart';

import 'error_page.dart';
import 'runtime_config.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.config,
    required this.onOpenSettings,
  });

  final RuntimeConfig config;
  final VoidCallback onOpenSettings;

  @override
  State<WebViewPage> createState() => WebViewPageState();
}

class WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? _controller;
  LoadFailureKind? _failure;
  List<UserScript> _scripts = const [];

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  /// 读构建期物化出的脚本清单，按运行期开关过滤。
  Future<void> _loadScripts() async {
    final enabled = widget.config.enabledScripts;
    final scripts = <UserScript>[];

    try {
      final manifest =
          jsonDecode(await rootBundle.loadString('assets/scripts/index.json'))
              as List<Object?>;

      for (final entry in manifest.whereType<Map<String, Object?>>()) {
        final id = entry['id']! as String;
        if (!enabled.contains(id)) continue;

        scripts.add(
          UserScript(
            groupName: id,
            source: await rootBundle.loadString('assets/scripts/$id.js'),
            // CSS 要等 DOM 有 head，hook 类脚本必须抢在页面脚本之前。
            injectionTime: entry['kind'] == 'css'
                ? UserScriptInjectionTime.AT_DOCUMENT_END
                : UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        );
      }
    } catch (e) {
      devLogger.warning('no inject scripts loaded: $e');
    }

    if (mounted) setState(() => _scripts = scripts);
  }

  /// 开关只在下一次页面加载生效（`WKUserContentController` 的语义），
  /// 所以设置页拨完开关必须调这个。
  Future<void> reloadWithCurrentSettings() async {
    await _loadScripts();
    await _controller?.setSettings(settings: _settings);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.config.url)),
    );
    if (mounted) setState(() => _failure = null);
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    userAgent: widget.config.userAgent,
    javaScriptEnabled: true,
    useOnLoadResource: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    supportZoom: false,
  );

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return ErrorPage(
        kind: failure,
        url: widget.config.url,
        onRetry: reloadWithCurrentSettings,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    return InAppWebView(
      key: ValueKey(_scripts.length),
      initialUrlRequest: URLRequest(url: WebUri(widget.config.url)),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView(_scripts),
      onWebViewCreated: (c) => _controller = c,
      onConsoleMessage: (_, msg) => devLogger.info('[console] ${msg.message}'),
      onReceivedError: (_, _, error) {
        devLogger.severe('load error: ${error.type} ${error.description}');
        // `WebResourceErrorType` 是 `@ExchangeableEnum` 生成出来的类，不是
        // 普通 Dart enum——没有 `.name` getter。用 `toValue()` 拿真实字符串。
        setState(
          () => _failure = classifyFailure(errorType: error.type.toValue()),
        );
      },
      onReceivedHttpError: (_, _, response) {
        devLogger.severe('http error: ${response.statusCode}');
        setState(
          () => _failure = classifyFailure(httpStatus: response.statusCode),
        );
      },
    );
  }
}
