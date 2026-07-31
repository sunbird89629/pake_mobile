import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger_utils/logger_utils.dart';

import 'error_page.dart';
import 'net/net_log.dart';
import 'net/net_record.dart';
import 'runtime_config.dart';

/// 当前生效脚本集合的稳定 key。
///
/// 只看集合内容，跟数量、顺序无关——「关 A 开 B」总数不变，但集合变了，
/// 必须换出一个新 key 才能强制 `InAppWebView` 的 Element 重建，
/// 否则 `initialUserScripts` 只在建 Element 时读一次，新脚本组合永远不会生效。
/// 同一个集合不管传入顺序如何都要给出同一个 key，否则会引发无意义的重建。
String scriptsKey(Iterable<String> ids) {
  final sorted = ids.toSet().toList()..sort();
  return sorted.join('\u0000');
}

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
  List<String> _scriptIds = const [];

  /// 两个互补的抓包来源汇合到这——JS hook（有 body）与 onLoadResource
  /// （只有 URL/时序）都往这里 add。`DebugDrawer` 的「View requests」经
  /// `GlobalKey<WebViewPageState>` 读它。
  final netLog = NetLog();

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  @override
  void dispose() {
    netLog.dispose();
    super.dispose();
  }

  /// 读构建期物化出的脚本清单，按运行期开关过滤。
  Future<void> _loadScripts() async {
    final enabled = widget.config.enabledScripts;
    final scripts = <UserScript>[];
    final ids = <String>[];

    try {
      final manifest =
          jsonDecode(await rootBundle.loadString('assets/scripts/index.json'))
              as List<Object?>;

      for (final entry in manifest.whereType<Map<String, Object?>>()) {
        final id = entry['id']! as String;
        if (!enabled.contains(id)) continue;

        ids.add(id);
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

    // 网络抓包 hook 必须排在用户脚本之前、AT_DOCUMENT_START 注入，
    // 否则页面早期发的请求就漏抓了。它会替换页面的 fetch/XHR，所以要留
    // 一个开关——设置页关掉后，这里就一句都不注入。
    if (widget.config.captureNetwork) {
      scripts.insert(
        0,
        UserScript(
          groupName: '__pake_net_hook',
          source: await rootBundle.loadString('assets/net_hook.js'),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _scripts = scripts;
        _scriptIds = ids;
      });
    }
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

    // WebView 需要铺满全屏（见设计文档的 全屏 运行时开关），不能像
    // `ErrorPage` 那样包 SafeArea——那会让内容避开刘海/底部安全区，
    // 并在横屏或全屏播放视频时产生黑边。
    return _webView;
  }

  Widget get _webView => InAppWebView(
    // 数量相同、内容不同的脚本切换（关 A 开 B）必须换 key，见 scriptsKey 的注释。
    key: ValueKey(scriptsKey(_scriptIds)),
    initialUrlRequest: URLRequest(url: WebUri(widget.config.url)),
    initialSettings: _settings,
    initialUserScripts: UnmodifiableListView(_scripts),
    onWebViewCreated: (c) {
      _controller = c;
      c.addJavaScriptHandler(
        handlerName: 'pakeNet',
        callback: (args) {
          if (args.isEmpty || args.first is! Map) return;
          netLog.add(
            NetRecord.fromHandlerJson(args.first as Map<Object?, Object?>),
          );
        },
      );
    },
    onLoadResource: (_, resource) => netLog.add(
      NetRecord(
        url: resource.url?.toString() ?? '',
        method: 'GET',
        status: 0,
        durationMs: resource.duration?.round() ?? 0,
        at: DateTime.now(),
        source: NetSource.resource,
      ),
    ),
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
