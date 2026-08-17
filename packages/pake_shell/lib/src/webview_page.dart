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

  /// 页面进了视频全屏（`WebChromeClient.onShowCustomView`）。此时不能再给
  /// 顶部留状态栏的位置，否则播放器上方挂一道黑边。
  bool _videoFullscreen = false;

  /// 状态栏那条留白的底色。
  ///
  /// 必须显式给：`PakeApp` 的 `home` 是裸 `Stack`，不填色就会露出
  /// `MaterialApp` 的浅色默认背景——深色站点顶上顶一条白杠。
  /// 目标站点多是深色，先钉死黑色；将来要跟随站点，读网页的
  /// `<meta name="theme-color">` 再换掉这一个常量即可。
  static const _statusBarBackdrop = Colors.black;

  /// WebView 的 key，直接从 `_scripts` 算——**不要**另存一份 id 列表。
  ///
  /// 曾经存过：抓包 hook 只进 `_scripts` 没进那份列表，于是拨 captureNetwork
  /// 开关时 key 纹丝不动，Element 复用，`initialUserScripts` 不重读，hook
  /// 关不掉也开不起来。少一个需要手动同步的副本，就少一种漏项的方式。
  String get _scriptsKey => scriptsKey(_scripts.map((s) => s.groupName ?? ''));

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

    if (mounted) setState(() => _scripts = scripts);
  }

  /// 开关只在下一次页面加载生效（`WKUserContentController` 的语义），
  /// 所以设置页拨完开关必须调这个。
  Future<void> reloadWithCurrentSettings() async {
    final keyBefore = _scriptsKey;
    final wasShowingError = _failure != null;

    await _loadScripts();
    if (!mounted) return;

    // WebView 会整个重建的两种情况：脚本集合变了（key 变），或刚从错误页
    // 回来（ErrorPage 分支把 InAppWebView 摘出过树，原生实例已销毁）。
    // 两种情况下新实例都自带最新的 initialSettings 与 initialUrlRequest，
    // 不需要——也不能——走 `_controller`：它指向的是旧的、已经或即将销毁的
    // 原生实例，碰它就是 `MissingPluginException`，而且异常会打断后面的
    // `setState`，把人永久卡在错误页上。
    if (wasShowingError) {
      setState(() => _failure = null);
      return;
    }
    if (_scriptsKey != keyBefore) return;

    await _controller?.setSettings(settings: _settings);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.config.url)),
    );
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

    // 沉浸式状态栏：targetSdk 36 起窗口强制边到边（API 36 上连
    // windowOptOutEdgeToEdgeEnforcement 都已失效），状态栏透明浮在内容之上，
    // 网页自己的顶栏会被压在底下。所以让 WebView 从状态栏 inset 下方开始，
    // 露出的那条用同一个底色填掉，视觉上跟站点顶栏连成一片。
    //
    // 用 Padding 而不是 `ErrorPage` 那样的 SafeArea：SafeArea 会连底部手势条
    // 和横屏两侧的刘海一起避让，播放器上下就多出黑边。这里只让顶部这一处。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 深色底配浅色图标。Android 看 statusBarIconBrightness，iOS 看
      // statusBarBrightness，两者语义相反，必须都给，否则总有一端是瞎的。
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: _statusBarBackdrop,
        child: Padding(
          // 视频全屏时必须归零：播放器要占满物理屏幕，留着这条 inset
          // 就是播放器上方的一道黑边。
          padding: EdgeInsets.only(
            top: _videoFullscreen ? 0 : MediaQuery.paddingOf(context).top,
          ),
          child: _webView,
        ),
      ),
    );
  }

  Widget get _webView => InAppWebView(
    // 数量相同、内容不同的脚本切换（关 A 开 B）必须换 key，见 scriptsKey 的注释。
    key: ValueKey(_scriptsKey),
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
    // 播放器进出全屏时，顶部那条状态栏留白要跟着让开／回来。
    onEnterFullscreen: (_) => setState(() => _videoFullscreen = true),
    onExitFullscreen: (_) => setState(() => _videoFullscreen = false),
    onConsoleMessage: (_, msg) => devLogger.info('[console] ${msg.message}'),
    onReceivedError: (_, request, error) {
      // 每个子资源（图片/XHR/字体……）失败都会触发这个回调，不只是主文档。
      // 只有主文档失败才该整页盖错误页——见 shouldSurfaceError 的空值策略注释。
      if (!shouldSurfaceError(isForMainFrame: request.isForMainFrame)) {
        devLogger.info(
          'sub-resource load error: ${error.type} ${error.description} '
          '(${request.url})',
        );
        return;
      }
      devLogger.severe('load error: ${error.type} ${error.description}');
      // `WebResourceErrorType` 是 `@ExchangeableEnum` 生成出来的类，不是
      // 普通 Dart enum——没有 `.name` getter。用 `toValue()` 拿真实字符串。
      setState(
        () => _failure = classifyFailure(errorType: error.type.toValue()),
      );
    },
    onReceivedHttpError: (_, request, response) {
      if (!shouldSurfaceError(isForMainFrame: request.isForMainFrame)) {
        devLogger.info(
          'sub-resource http error: ${response.statusCode} (${request.url})',
        );
        return;
      }
      devLogger.severe('http error: ${response.statusCode}');
      setState(
        () => _failure = classifyFailure(httpStatus: response.statusCode),
      );
    },
  );
}
