# 底部悬浮工具栏设计

给 pake 壳加一条浮在网页之上的底部胶囊工具栏，三个按钮：后退、刷新、设置。
上滑隐藏、下滑显示，带动画。同时接管系统返回键，并**删除**左上角长按的
`EscapeHatch`。

## 决策记录

| 问题 | 结论 |
|---|---|
| 放几个按钮 | 三个：后退 / 刷新 / 设置。**不要前进** |
| 系统返回键 | 一并接管：有网页历史则回退，无历史则直接退出。不做「再按一次退出」 |
| 后退按钮禁用态 | 做。`onLoadStop` + `onUpdateVisitedHistory` 时异步查 `canGoBack()` |
| 滚动阈值 | 累计 10 逻辑像素才翻转一次状态，翻转后重置锚点 |
| 页面顶部 | `y < 栏高` 时无条件显示 |
| 换页 | `onLoadStop` / `onUpdateVisitedHistory` 时重置为显示 |
| 摆放 | 坐在系统手势条**之上**，栏下方露出一条网页 |
| 形态 | 悬浮胶囊：居中、全圆角、不透明深色底 + 阴影、白色图标 |
| 动画 | `AnimatedSlide` `offset(0,2)`，200ms，`Curves.easeOut`。不叠淡出 |
| `EscapeHatch` | **删除** |
| 可配置关闭 | **不可以**。加了会自我锁死 |
| 刷新按钮调什么 | `_controller.reload()`，**不是** `reloadWithCurrentSettings()` |
| 状态归谁 | 全在 `WebViewPageState`，不上提到 `app.dart` |

## 几条需要留意的

### 为什么没有「前进」

单站点壳里「前进」只有在刚点过后退之后才有意义，绝大多数时间是灰的。
一个常年禁用的按钮是纯噪音，砍掉它同时省掉「不可用时变灰还是隐藏」这个分支。

### 删掉 `EscapeHatch` 的代价与由此产生的硬约束

`EscapeHatch` 是左上角 44×44 的长按识别区，而左上角正是移动站放汉堡菜单和
返回按钮的地方——在那块区域长按网页里的链接或图片，会打开设置而不是弹出
网页的上下文菜单（`translucent` 只保证短按穿透，长按会被抢走）。删掉它就是
为了消掉这个冲突。

代价是**设置只剩胶囊上的 ⚙ 和错误页那个按钮**。这直接导出一条硬约束：

> **这条栏绝不能做成可配置关闭。**

一旦允许关掉，用户在设置页关掉它 → 退出设置 → 没有任何入口能再打开设置 →
app 真的砖了，只能卸载重装。这是不可逆的自我锁死。要加开关就必须同时把
`EscapeHatch` 留着，二选一。

### 「卡在隐藏态」这条路是怎么堵死的

能让栏重新出现的触发点有四个：滑到顶部、上滑 10px、`onLoadStop`、
`onUpdateVisitedHistory`。

最危险的场景是「长页面滑下去把栏藏了 → 点进一个短到不能滚动的页面」——短页面
永远不会触发 `onScrollChanged`，栏出不来，那个页面上既没有后退也没有设置。
换页重置就是专门堵它的。

推演下来只剩一个残余场景：网页弹出模态框并 `overflow:hidden` 锁死滚动，此时
栏若正好是隐藏的就出不来。但用户总能关掉那个模态框（那是网站自己的 UI），
关掉后上滑即可。**明确决定不为它加额外机制**——比如「N 秒无滚动自动显示」
要多一个计时器，还会在正常阅读时莫名弹出来。

### 刷新按钮不能调 `reloadWithCurrentSettings()`

那个方法最后一行是：

```dart
await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.config.url)));
```

它加载的是**配置里的首页 URL**，不是当前页。设置页调它是对的（改完 UA/脚本
要从头来），但绑到刷新按钮上，用户在站内点进第三层详情页按一下刷新就被扔回
首页。

刷新按钮调 `_controller?.reload()`，只重载当前页。它因此**不会**重新应用刚改的
设置——这是对的，设置页保存时自己已经调了 `reloadWithCurrentSettings()`。

### `PopScope` 在 Navigator 之上是失效的

`_PopScopeState.didChangeDependencies` 这样注册（Flutter 3.41.2
`pop_scope.dart:190`）：

```dart
final ModalRoute<dynamic>? nextRoute = ModalRoute.of(context);
if (nextRoute != _route) {
  _route?.unregisterPopEntry(this);
  _route = nextRoute;
  _route?.registerPopEntry(this);   // ← 空安全，null 就什么都不做
}
```

而 `LockScreen` 的 `PopScope(canPop: false)` 挂在 `MaterialApp.builder` 里，
**在 Navigator 之上**（`pin_gate.dart` 的类注释自己写了这一点）。Navigator 之上
没有 `ModalRoute`，`ModalRoute.of(context)` 返回 null，**那个 `PopScope` 一行
作用都没有**。

改动之前看不出来：壳里没有别的 `PopScope`，也没有可回退的路由，返回键就是
退出 app——看起来「锁屏挡住了」，其实只是碰巧。

加了返回键接管之后这个潜伏问题会变成真的：锁屏亮着时按返回键会去调下面那个
被遮住的 WebView 的 `goBack()`，用户看不见，但解锁后发现页面变了。

**解法**：`PinGate` 把 `_locked` 用 `ValueNotifier` 往下传，返回键处理器在锁着时
直接 return。锁屏期间按返回键**什么都不做**（不退出 app），这跟 `LockScreen`
作者原本的意图一致。

代价是 `WebViewPage` 认识了锁的存在。这个耦合是**真实存在的语义依赖**
（「锁着的时候不响应导航」），显式写出来比藏着好。

## 架构

```
packages/pake_shell/lib/src/bottom_bar.dart          新：无状态胶囊
packages/pake_shell/lib/src/webview_page.dart        改：滚动/历史状态 + 挂载 + PopScope + 纯函数
packages/pake_shell/lib/src/app.dart                 改：移除 EscapeHatch
packages/pake_shell/lib/src/lock/pin_gate.dart       改：暴露 ValueListenable<bool> locked
packages/pake_shell/lib/src/escape_hatch.dart        删
packages/pake_shell/lib/src/error_page.dart          改：注释里「EscapeHatch 兜底」的说法
packages/pake_shell/test/bottom_bar_test.dart        新
packages/pake_shell/test/webview_page_test.dart      改：+ barStateAfterScroll 用例
packages/pake_shell/test/escape_hatch_test.dart      删（166 行）
packages/pake_shell/test/error_page_test.dart        改：同上，只改注释
README.md                                            改：设置页入口 + 应用锁两处描述
docs/manual-regression.md                            改：+ 真机验证点
```

### 挂载点

`webview_page.dart` 现有结构是 `AnnotatedRegion > ColoredBox > Padding > _webView`。
把 `Padding` 的 child 换成 `Stack`：

```dart
child: Stack(
  children: [
    _webView,
    Positioned(
      left: 0,
      right: 0,
      // 摆法 B：坐在手势条之上，栏下方露出一条网页。
      bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
      child: BottomBar(...),
    ),
  ],
),
```

状态放 `WebViewPageState` 而不是 `app.dart`，因为这条栏需要的四样东西——滚动
位置、`_videoFullscreen`、`_controller`（`goBack`/`reload`）、`onOpenSettings`
——**已经全在 `WebViewPageState` 里了**。放 `app.dart` 的 `Stack` 里就得靠
`_webViewKey` 把这些反向捞上去。

`build` 开头的 `if (failure != null) return ErrorPage(...)` 早返分支天然把栏排除
在错误页之外，而错误页本来就有自己的设置按钮，不会重复。

### 滚动判定抽成纯函数

`webview_page.dart` 里已经是这个模式（`scriptsKey` / `shouldSurfaceError` /
`classifyFailure` 都是顶层纯函数 + 独立测试）。照办：

```dart
({bool visible, int anchor}) barStateAfterScroll({
  required int y,
  required int anchor,
  required bool visible,
  required double barHeight,
});
```

覆盖：阈值内不翻转、超阈值翻转并重置锚点、`y < barHeight` 无条件显示、方向反转。

`WebViewPage` 整体仍然不做 widget test（`InAppWebView` 是平台视图，测不了），
跟现状一致。`BottomBar` 是纯 `StatelessWidget`，可以直接 widget test。

### 触发信号

`flutter_inappwebview` 的 `onScrollChanged(controller, x, y)`——Android 走
`WebView.onScrollChanged`，iOS 走 `UIScrollViewDelegate.scrollViewDidScroll`，
两端都是原生实现（`platform_webview.dart:459`）。WebView 是平台视图，Flutter 的
手势竞技场看不到它内部的触摸，所以这是唯一可行的信号源。

`onUpdateVisitedHistory(controller, url, isReload)` 连 SPA 的
`pushState` / `replaceState` / hash 变化都会触发，是刷新「能不能后退」和重置
栏可见性的正确钩子——目标站点基本都是 SPA。

### `IgnorePointer` 是必须的

位移后的命中测试理论上会跟着变换走，但这条栏盖的是网页的可点区域。不赌
`PlatformView` 的命中测试在 `FractionalTranslation` 下的行为，隐藏时显式
`IgnorePointer(ignoring: true)`。

`offset` 给 2 而不是 1：摆法 B 让胶囊离底边有一段距离，只移动 1 倍高度它还有
一半挂在缝里。多出来的行程被 `Stack` 默认的 `Clip.hardEdge` 裁掉。

## 已知代价

**遮挡**。栏浮在网页上（这是需求），显示时会盖住网页底部一块。很多移动站的
底部 tab bar 正好在那——栏可见时那些按钮点不到。缓解手段就是滑动自动隐藏
本身，以及胶囊形态（比通栏窄，两侧的网页按钮还能点）。

不接受遮挡的唯一替代是让 WebView 缩高（栏挤占布局而非悬浮），但那跟「浮在
网页上面」的需求冲突，且每次显隐都会触发网页 reflow，视频播放器会跟着抖。

**测不到的部分**。`bottom_bar_test.dart` 能验证「按钮点了会调回调」「禁用时
不调」，但验证不了动画和滚动联动——那部分只能靠纯函数测 + 真机手验。

## 真机验证点

两个读代码确定不了、必须真机校准的：

1. **`onScrollChanged` 的 `y` 单位**。Android 原生 `WebView.onScrollChanged`
   给的是设备像素，插件是否转成逻辑像素没在源码里确认到。如果是设备像素，
   10px 阈值在 3x 屏上会过于灵敏。真机打印一次 `y` 就能定，必要时按
   `devicePixelRatio` 换算。

2. **内层滚动容器**。有些站点的滚动发生在内层 `div` 而不是 document 上，
   `onScrollChanged` 不触发，栏就永远不隐藏。这不会导致砖（栏保持可见），
   但「上滑隐藏」在那类站点上不生效。

以及常规手验：

3. 上滑隐藏 / 下滑显示的动画是否跟手，10px 阈值会不会抖。
4. 滑到页面顶部时栏必然出现。
5. 从长页面点进不可滚动的短页面，栏必然出现。
6. 视频进全屏时栏消失，退出全屏时回来。
7. 后退按钮在首页是灰的，点进二级页后变亮。
8. 系统返回键：有历史时回退，无历史时退出 app。
9. 锁屏亮着时按系统返回键——什么都不做，解锁后页面没变。
10. 刷新按钮停在当前页，不回首页。
11. 栏可见时，网页底部两侧的按钮仍能点到。
