# Claude Code 工作日志

按时间倒序记录排查结论。每条包含：现象 → 机制 → 修法 → 验证点。

---

## 2026-08-17 沉浸式状态栏

**现象**

真机上系统状态栏（时间、电量、WiFi）与网页自己的顶栏（站点 logo、汉堡菜单）
重叠，页面内容被压在状态栏底下。

**机制**

两件事叠加，缺一不会出问题：

1. **窗口强制边到边**。`targetSdk = 36`（Flutter 3.41.2 的
   `FlutterExtension.kt:34`）。Android 15（API 35）起强制 edge-to-edge，到
   API 36 连 `windowOptOutEdgeToEdgeEnforcement` 这个退出开关都已失效——
   窗口必然边到边，状态栏透明浮在内容之上。
2. **WebView 故意不避让**。原注释写着「WebView 需要铺满全屏……不能像
   `ErrorPage` 那样包 SafeArea」，于是网页从物理 y=0 开始渲染。

`escape_hatch.dart` 的注释其实早就写明「app 边到边绘制」，并自己用
`MediaQuery.padding.top` 做了避让——那是全代码库唯一处理过状态栏 inset 的
地方，WebView 没跟上。

**一处定性更正**

排查中一度把 `RuntimeConfig.fullscreen` 判定为「又一个接了一半的开关」，
**这个说法是错的**。`docs/superpowers/plans/2026-07-30-pake-mobile.md:5888`
明确记着：spec 列的「全屏 / 手势 / 缓存策略 / 日志级别」四项只在 `RuntimeKeys`
里预留常量、不做设置页 UI，判断为 YAGNI，「如果需要，另开一个小任务」。

所以它是**有意预留**，跟 `captureNetwork` 那种「链路断在中间」性质完全不同。
本次改动就是文档里说的那个「另开的小任务」，且**没有动 `fullscreen` 字段**——
接不接那个开关是独立决策。

**修法（已应用）**

`webview_page.dart` 的 `build()` 里包三层：

```dart
return AnnotatedRegion<SystemUiOverlayStyle>(
  value: const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android
    statusBarBrightness: Brightness.dark,      // iOS，语义相反
  ),
  child: ColoredBox(
    color: _statusBarBackdrop,
    child: Padding(
      padding: EdgeInsets.only(
        top: _videoFullscreen ? 0 : MediaQuery.paddingOf(context).top,
      ),
      child: _webView,
    ),
  ),
);
```

外加 `_videoFullscreen` 字段、`_statusBarBackdrop` 常量，以及
`onEnterFullscreen` / `onExitFullscreen` 两个回调。

三个决定的理由：

- **用 `Padding` 不用 `SafeArea`**。原注释担心的黑边是真的：SafeArea 会把
  底部手势条和横屏两侧刘海一并避让。只让顶部这一处，横屏与底部不受影响。
  原注释已改写成现在的依据，否则会误导后人去掉这段。
- **底色必须显式给**。`PakeApp` 的 `home` 是裸 `Stack`，不填色会露出
  `MaterialApp` 的浅色默认背景——深色站点顶上顶一条白杠。先钉死黑色；将来
  要跟随站点，读网页的 `<meta name="theme-color">` 换掉那一个常量即可。
- **两个 brightness 都要给**。Android 看 `statusBarIconBrightness`，iOS 看
  `statusBarBrightness`，语义相反，只给一个就有一端是瞎的。

**关于视频全屏那两个回调**

Android 的 `onShowCustomView` 是把播放器挂到 activity 的 decor view 上，会盖住
整个 Flutter 树（包括那条 padding），所以归零这一步**在 Android 上很可能是
空操作**。但 `_settings` 开了 `allowsInlineMediaPlayback: true`，站点用 JS
Fullscreen API 做内联全屏时播放器仍在 webview 内部，那种情况下这两行是必需的。
成本两行，留着。

**验证点**（都需要真机）

- [ ] 网页顶栏完整露出，黑条与站点顶栏接得上、看不出缝
- [ ] 播放视频进全屏，播放器上方没有多出黑边
- [ ] `EscapeHatch` 长按仍能进设置——它在 `Stack` 里与 WebViewPage 平级，
      仍按 `padding.top` 定位，理论上不受影响

**未处理**：底部。edge-to-edge 同样让页面延伸到手势条下面，只是底部是滚动
内容、可以滑上来，不像固定顶栏那样挡死。要处理就是同一个 `EdgeInsets` 再加
一个 `bottom`。

---

## 2026-08-17 开发期脚本调试链路

**问题**：注入脚本由 `pakem build` 物化进 `assets/scripts/`，所以直接跑
`packages/pake_shell/lib/main.dart` 调试时一个脚本都没有，改脚本必须走完整构建。

**做法**：把物化单独拎出来给开发期用，但**必须是同一个函数**——id 规则各写
一份就会重演 `pake_config/lib/src/script_id.dart` 记的那个坑（壳算出的启用集合
跟物化产物对不上，两边测试还都是绿的）。

| 文件 | 改动 |
|---|---|
| `pake_cli/lib/src/materialize.dart` | `_materializeScripts` → 公开 `materializeScriptsInto({config, outDir, cwd, preserve})` |
| `pake_cli/lib/pake_cli.dart` | 新建，只导出物化这一小块 |
| `pake_shell/pubspec.yaml` | dev_dependencies 加 `pake_cli`(path) + `path` |
| `pake_shell/tool/dev_scripts.dart` | 新建，开发期物化工具 |
| `pake_shell/.gitignore` | 忽略 `dev_scripts/` 与 `assets/scripts/*`，放行 `.gitkeep` |

用法：

```bash
cd packages/pake_shell
# 脚本放 dev_scripts/，路径填进 assets/pake.json 的 injectScripts
dart run tool/dev_scripts.dart
# 然后 hot restart（R）
```

不用手动 `rootBundle.evict`：reassemble 会清掉 asset 缓存，`initState` 重跑
`_loadScripts()` 就读到新内容。

**两个踩点**：

- `preserve` 参数是为 `.gitkeep` 加的。原逻辑把目录里所有不在 `wanted` 的文件
  当上一次构建的残留删掉；生产环境的 workspace 是生成的无所谓，但开发期直接写
  模板仓库，会把签入的 `.gitkeep` 删掉。
- 新增脚本后如果不生效，是 `RuntimeConfig.enabledScripts` 的存量覆盖：设置页
  拨过一次开关后 `pake.enabledScripts` 就写死进 GetStorage 了，新 id 不在那个
  集合里。去设置页 Reset 一次。

**安全性**：`syncTemplate` 绕开 `assets/pake.json` 与 `assets/scripts/` 整棵
子树（见 `_ownedByMaterialize`），真实构建里这两处由 `materializeConfig` 重写，
所以模板仓库里放的 dev 内容不会跟着用户构建的 app 走。

---

## 2026-08-17 两个 WebView 缺陷（已修）

开发中直接跑 `packages/pake_shell/lib/main.dart` 时暴露。两者独立，但都源于
`WebViewPageState` 里「Dart 侧状态」与「原生 WebView 实例状态」的不同步。

> 本节引用的 `webview_page.dart` 行号是**修复前**的位置，修完已经全部偏移；
> 定位请按字段名和函数名找。

### 1. 错误页重试抛 `MissingPluginException`

**现象**

```
E/flutter: Unhandled Exception: MissingPluginException(No implementation found
           for method setSettings on channel com.pichillilorenzo/flutter_inappwebview_0)
#1  AndroidInAppWebViewController.setSettings
#2  WebViewPageState.reloadWithCurrentSettings (webview_page.dart:119)
```

**机制**

`_controller` 只在 `onWebViewCreated` 里赋值，从不置空（`webview_page.dart:40, 159-160`）。
而页面加载失败后 `build()` 走 ErrorPage 分支（`webview_page.dart:137-145`），
`InAppWebView` 整个从 widget 树上被摘掉，原生实例随之销毁——`_controller` 就成了
指向已销毁实例的悬垂引用：

```
onReceivedError → setState(_failure = ...)
  → build() 返回 ErrorPage，InAppWebView 卸载，原生实例销毁
  → _controller 悬垂
  → 点「重试」→ reloadWithCurrentSettings()
  → _controller.setSettings() → 原生端找不到 channel …_webview_0 → 抛
```

**连带后果（更严重）**：异常发生在 `setState(() => _failure = null)`
（`webview_page.dart:123`）**之前**，所以错误页永远清不掉——重试按钮点几次抛几次，
用户卡死在错误页，只能杀进程。

**修法（已应用）**

WebView 重建时会自带最新的 `initialSettings` + `initialUrlRequest`，本就不需要
碰 controller。所以先判断「这次会不会重建」，会就直接 return：

```dart
Future<void> reloadWithCurrentSettings() async {
  final keyBefore = _scriptsKey;
  final wasShowingError = _failure != null;

  await _loadScripts();
  if (!mounted) return;

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
```

两处与最初设想的方案不同，值得记下来：

- **重建路径有两条，不止错误页**。脚本集合变化（key 变）同样会重建 Element、
  销毁旧原生实例，所以必须比较 `_scriptsKey` 前后，只处理错误页是不够的。
- **没有把 `_controller` 置空**。看着更"干净"，但有时序风险：`_loadScripts`
  里的 `setState` 已经排上了重建，若 key 变了，新实例的 `onWebViewCreated`
  可能已经把新 controller 写进来，此时置空反而把有效的新引用抹掉。悬垂引用的
  唯一使用者就是本函数，函数自己避开就够了。

**验证点**：把 URL 改成一个必然失败的地址 → 进错误页 → 点重试 → 不抛异常；
再把 URL 改回可用地址 → 重试 → 正常回到页面。

### 2. 抓包开关（`captureNetwork`）拨了不生效

**现象**

设置页拨 `captureNetwork` 开关后，抓包 hook 该关的关不掉、该开的开不起来，
直到 app 重启。

`docs/manual-regression.md` 第 18-19 行那条回归项（「关掉一个注入脚本开关
（比如 Capture network）→ reload 后脚本真的不生效了」）测的正是这个场景，
但实现是坏的。

**机制**

`_loadScripts()` 维护两个列表，net hook 只进了其中一个：

```dart
ids.add(id);                    // line 77 — 只有 index.json 里的脚本进 ids
scripts.add(UserScript(...));

// line 96-105
if (widget.config.captureNetwork) {
  scripts.insert(0, UserScript(groupName: '__pake_net_hook', ...));
  //                ↑ 只进 scripts，没进 ids
}
```

而 WebView 的 key 是 `ValueKey(scriptsKey(_scriptIds))`（`webview_page.dart:155`）：

```
_scripts 变了（多/少一条 hook） → setState
_scriptIds 没变                 → key 没变
                                → Element 复用，不重建
                                → initialUserScripts 不重读（只在建 Element 时读一次）
                                → webview 里注入的还是老集合
```

`reloadWithCurrentSettings()` 里的 `loadUrl` 救不了：UserScript 注册在 webview
实例上，重新导航只是把**注册时那份老集合**再注入一遍。

**dev 壳是最极端的情况**：`assets/pake.json` 里 `injectScripts: []` →
`_scriptIds` 恒为空 → key 恒为 `''` → WebView 永远不重建 → 开关 100% 失效。

这与 `packages/pake_config/lib/src/runtime_keys.dart:12-14` 的意图直接矛盾——
那条注释说这个键存在的全部理由就是「没有它用户就关不掉抓包 hook」。

**修法（已应用）**

别从手动维护的第二个列表算 key，直接从 `_scripts` 本身算。`_scriptIds` 字段
连同 `_loadScripts()` 里那份 `ids` 一起删掉，换成一个 getter：

```dart
String get _scriptsKey => scriptsKey(_scripts.map((s) => s.groupName ?? ''));
```

这样任何进入注入集合的脚本都自动纳入 key，不再存在「两个列表要记得同步」
这个 bug 源头。`scriptsKey` 仍是纯函数，`test/webview_page_test.dart` 的 4 个
case 不受影响。

**验证点**：即 `docs/manual-regression.md` 已有的那条——拨掉 Capture network →
reload → DebugDrawer 的 View requests 不再有 JS hook 来源的记录（只剩
`onLoadResource` 那一路）。

### 共同教训

两处都是同一类错误：**Dart 侧记了一份状态，原生 WebView 侧记了另一份，
中间没有强制同步的机制**。

- 缺陷 1 是 `_controller` 比原生实例活得久；
- 缺陷 2 是 `_scriptIds` 比 `_scripts` 少一条。

对策也一致：**要么别让第二份状态存在，要么让使用方自己判断它还有没有效**。
缺陷 2 走了前者（key 从真正注入的 `_scripts` 直接算，删掉副本）；缺陷 1 走了
后者（`reloadWithCurrentSettings` 自己判断 WebView 会不会重建），因为强行清空
`_controller` 反而引入了新的时序竞争。

### 关于回归测试

**两处都没有加自动化测试**，这是有意的：

- `InAppWebView` 是 platform view，单元测试里起不来。`test/` 下 11 个文件没有
  一个 mount 过 `WebViewPage`，两处提到它的地方都只是注释。
- 缺陷 2 想在纯函数层面造测试的话，得重新引入一份「注入了哪些脚本」的平行表示
  ——那正是这个 bug 的成因。写出来的测试在修复前后都会通过，等于没有守住任何
  东西。修复的保障是结构性的：没有第二个列表可漏。
- 真正的守卫是 `docs/manual-regression.md:18-19` 那条（拨掉 Capture network →
  reload → 脚本真的不生效），需要真机执行。

`flutter analyze` 干净，`pake_shell` 96 个测试、`pake_cli` 120 个测试仍全绿。

---

## 附：`assets/scripts/index.json` 加载失败是正常的

```
WARNING devLogger: no inject scripts loaded: Unable to load asset:
"assets/scripts/index.json". The asset does not exist or has empty data.
```

`assets/scripts/` 在模板仓库里只有一个 `.gitkeep`，`index.json` 由物化生成
（`packages/pake_cli/lib/src/materialize.dart:226`）。没跑过物化自然没有这个
文件；且 `assets/pake.json` 里 `injectScripts: []`，本来也没脚本要注入。

`_loadScripts()` 把它 catch 成 warning（`webview_page.dart:93-94`），就是为
这个场景设计的。**不是 bug，忽略。**

**跑过 `tool/dev_scripts.dart` 之后这条 warning 会消失**：即使
`injectScripts` 是空的，工具也会写出一个内容为 `[]` 的 `index.json`，于是
`_loadScripts()` 正常解析出空清单，不再走 catch 分支。两种情况行为等价
（都是没有用户脚本），只是日志少一行。
