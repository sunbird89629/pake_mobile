import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger_utils/logger_utils.dart';

import 'bottom_bar.dart';
import 'error_page.dart';
import 'net/net_log.dart';
import 'net/net_record.dart';
import 'runtime_config.dart';

/// 底部栏翻转显隐所需的累计位移，逻辑像素。
///
/// 逐像素反应会让手指微抖就闪烁，所以要攒够一次「明确的滑动意图」才动。
const _barScrollThreshold = 10;

/// 滚动一步之后，底部栏该显示还是隐藏，以及新的比较锚点。
///
/// [y] 是当前纵向滚动位置，[anchor] 是上次翻转时记下的位置，[visible] 是当前
/// 状态，[barHeight] 是「算不算在页面顶部」的阈值。
///
/// 抽成纯函数是因为 `WebViewPage` 整体测不了（`InAppWebView` 是平台视图），
/// 而这段判定是整个特性里唯一有分支的逻辑——跟 [scriptsKey]、
/// `shouldSurfaceError`、`classifyFailure` 一样，放在这里换来可测。
({bool visible, int anchor}) barStateAfterScroll({
  required int y,
  required int anchor,
  required bool visible,
  required double barHeight,
}) {
  // 顶部无条件显示。用户找不到入口时的本能动作就是一路滑到顶，没有这条
  // 他会在顶部却看不到栏，以为坏了。
  if (y < barHeight) return (visible: true, anchor: y);

  final delta = y - anchor;
  // 攒不够阈值就连锚点都不动——锚点必须留在原地继续累计，否则永远攒不满。
  if (delta.abs() < _barScrollThreshold) {
    return (visible: visible, anchor: anchor);
  }

  // 下滑（y 变大）隐藏，上滑（y 变小）显示。翻转后锚点归到当前位置，下一次
  // 判定从这里重新累计，避免锚点被甩在很远的地方。
  return (visible: delta < 0, anchor: y);
}

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
    required this.locked,
  });

  final RuntimeConfig config;
  final VoidCallback onOpenSettings;

  /// 应用锁当前是不是锁着的，由 `LockGate` 写、这里只读。
  ///
  /// 这个耦合是真实存在的语义依赖——「锁着的时候不响应导航」——而不是顺手
  /// 传下来的。`LockScreen` 自己那个 `PopScope(canPop: false)` 挂在
  /// `MaterialApp.builder` 里、在 Navigator **之上**，`ModalRoute.of` 返回
  /// null，`_PopScopeState` 的注册是空安全的，所以它一行作用都没有。挡返回
  /// 键只能挡在这里。
  final ValueListenable<bool> locked;

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

  /// 主文档加载进度，0-100。
  ///
  /// 用 `ValueNotifier` 而不是 `setState`：一次加载 `onProgressChanged` 会来
  /// 几十次，`setState` 就把整棵子树（含 `BottomBar` 和平台视图外壳）重建同样
  /// 次数。跟 `onScrollChanged` 那里同一个考量——只让进度条自己重建。
  final _progress = ValueNotifier<int>(0);

  /// 底部栏是否可见，以及上次翻转时的滚动位置。见 [barStateAfterScroll]。
  bool _barVisible = true;
  int _scrollAnchor = 0;

  /// 网页还有没有可回退的历史。`canGoBack()` 是异步的平台往返，不能在
  /// `build` 里同步读，只能在导航事件里查一次存下来。因此它永远滞后一帧
  /// 左右——人眼看不出来，但测试里要 `pumpAndSettle` 而不是 `pump`。
  bool _canGoBack = false;

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
    _progress.dispose();
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

  /// 导航到了新地址（含 SPA 的 pushState/replaceState/hash 变化）。
  Future<void> _onNavigated(InAppWebViewController controller) async {
    final canGoBack = await controller.canGoBack();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      // 换页必须把栏放出来。否则：在长页面滑下去把栏藏了，再点进一个短到
      // 不能滚动的页面——那个页面永远不触发 onScrollChanged，栏就再也出不
      // 来，用户在那一页既没有后退也没有设置。
      _barVisible = true;
      _scrollAnchor = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.locked,
      builder: (context, locked, _) => PopScope(
        // 没锁且没有网页历史时放行，由框架 pop 根路由 = 退出 app，不必自己
        // 调 SystemNavigator.pop。锁着时一律拦下且什么都不做——见
        // `WebViewPage.locked` 上关于 LockScreen 那个失效 PopScope 的说明。
        canPop: !locked && !_canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || locked) return;
          _controller?.goBack();
        },
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
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
          child: Stack(
            // expand 而不是默认的 loose：loose 下 `_webView` 拿到的是宽松
            // 约束，撑不撑满取决于 PlatformView 自己的定尺行为。这里要的是
            // 「网页铺满，胶囊浮在上面」，就把它钉死。
            fit: StackFit.expand,
            children: [
              _webView,
              // 贴在网页内容顶边（状态栏留白已经由外层 Padding 让开），跟浏览
              // 器的位置惯例一致。
              Positioned(top: 0, left: 0, right: 0, child: _progressBar),
              Positioned(
                left: 0,
                right: 0,
                // 坐在系统手势条**之上**，栏下方露出一条网页。贴着物理底边
                // 会让栏的背景垫住手势条，看着更整，但那样它就不像浮层了。
                bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
                child: BottomBar(
                  // 视频全屏时一并收走：播放器要占满物理屏幕。
                  visible: _barVisible && !_videoFullscreen,
                  canGoBack: _canGoBack,
                  onBack: () => _controller?.goBack(),
                  // 不是 reloadWithCurrentSettings：那个方法最后会 loadUrl
                  // 到配置里的**首页** URL，绑在刷新上会把深层页面的用户扔
                  // 回首页。刷新就是重载当前页。
                  onReload: () => _controller?.reload(),
                  onOpenSettings: widget.onOpenSettings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部加载进度条。加载完成后淡出而不是立刻消失——`onProgressChanged` 到
  /// 100 和页面真正可读之间还差最后一次渲染，立刻抽走会让人觉得条走完了页面
  /// 还是空的。
  Widget get _progressBar => ValueListenableBuilder<int>(
    valueListenable: _progress,
    builder: (context, progress, _) => IgnorePointer(
      // 不挡住网页顶边那 2px：站点的顶栏按钮就在那儿。
      child: AnimatedOpacity(
        opacity: progress >= 100 || _videoFullscreen ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: LinearProgressIndicator(
          value: progress / 100,
          minHeight: 2,
          // 默认的浅色轨道在深色站点上是一条贯穿全宽的亮杠，比进度本身还显眼。
          backgroundColor: Colors.transparent,
        ),
      ),
    ),
  );

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
    // WebView 是平台视图，Flutter 的手势竞技场看不到它内部的触摸，所以这是
    // 判断滑动方向的唯一信号源（Android: WebView.onScrollChanged，
    // iOS: UIScrollViewDelegate.scrollViewDidScroll，都是原生实现）。
    onScrollChanged: (_, x, y) {
      final next = barStateAfterScroll(
        y: y,
        anchor: _scrollAnchor,
        visible: _barVisible,
        barHeight: BottomBar.height,
      );
      _scrollAnchor = next.anchor;
      // 这个回调每几毫秒就来一次，只有真翻转了才能 setState。
      if (next.visible != _barVisible) {
        setState(() => _barVisible = next.visible);
      }
    },
    onProgressChanged: (_, progress) => _progress.value = progress,
    onLoadStop: (controller, _) => _onNavigated(controller),
    // 连 SPA 的 pushState/replaceState/hash 变化都会触发——目标站点基本都是
    // SPA，只靠 onLoadStop 会漏掉站内的绝大多数跳转。
    onUpdateVisitedHistory: (controller, url, isReload) =>
        _onNavigated(controller),
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
