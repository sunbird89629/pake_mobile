---

pake_mobile 项目的开发日志，开发过程中的信息及时保存到这个文档

---


# Pake（tw93/Pake）功能分析 & 可借鉴清单

> 分析日期：2026-08-19
> 项目地址：https://github.com/tw93/Pake （60.9k ⭐）
> 一句话：`pake <url> --name <name>` 一条命令把任意网页打包成桌面应用（macOS / Windows / Linux）

## 一、项目概览

- **技术栈**：Rust + Tauri v2（不是 Electron），安装包通常 <10M，比 Electron 小近 20 倍
- **产品形态**：网页壳（webview wrapper），与 pake_mobile 同理念的桌面版兄弟项目
- **使用分层**：① 下载预打包的 Popular Packages ② CLI 一键打包 ③ 克隆源码自定义开发
- **开源协议**：GPL-3.0 + 输出例外条款（用 Pake 构建的应用归用户所有）
- **CLI 关键设计**：`--config app.json` 声明式配置、`--json` 机器可读输出、GitHub Actions 在线构建兜底

## 二、功能全景（按模块）

| 模块 | 能力 |
|---|---|
| **导航/快捷键** | 前进后退、缩放(±)、刷新、复制当前 URL、回主页、页内查找(Cmd/Ctrl+F)、清除缓存重启 |
| **窗口管理** | 无边框/沉浸、全屏、最大化、置顶、多窗口、多实例、拖拽移动 |
| **系统集成** | 系统托盘、关窗隐藏、启动进托盘、激活快捷键、网页通知→系统通知、Dock 徽标、下载处理 |
| **内容定制** | 样式注入(去广告)、JS 注入、自定义 UA、强制深色、禁用 web 快捷键 |
| **导航控制** | 强制内部导航、内部 URL 正则、安全域名白名单、新窗口放行、页内查找 |
| **隐私/网络** | 无痕模式(不存 cookie)、忽略证书错误、代理(socks5/http)、User-Agent |
| **构建/CLI** | `--config` 声明式、`--json` 机器输出、图标自动生成、多架构、预设应用列表 |

## 三、pake_mobile 已有 / Pake 没有的（无需借鉴）

- 底部栏（后退/刷新/设置）、返回键接管
- 手势图案锁
- 抓包 hook + NetLog
- 注入脚本体系 + 设置页开关（enabledScripts）
- 两层 RuntimeConfig（build-time asset + runtime GetStorage）
- 顶部加载进度条
- 错误页分类（shouldSurfaceError / classifyFailure）
- 预设站点体系（4kvm / dadatu / youtube）
- `pakem icon` 图标生成

## 四、值得借鉴的 / 不借鉴的

结论已抽成 [`roadmap.md`](./roadmap.md) 逐条维护——想做的按「近期 / 以后」分档，
决定不做的连同理由留在「不做」一节。这里不再重复，改动去那边改。

## 五、Pake 内部结构参考

- **注入脚本** `src-tauri/src/inject/`：auth.js / custom.js / event.js / find.js / fullscreen.js / style.js / theme_refresh.js / toast.js
- **Rust 命令层** `src-tauri/src/app/`：cert.rs / config.rs / invoke.rs / menu.rs / navigation.rs / setup.rs / window.rs
- **关键注入脚本职责**：
  - `style.js` — 去广告 CSS + 沉浸式头部适配（无标题栏时给各站点头部加 padding-top，非 mac 顶部加 20px 可拖拽条）
  - `event.js` — 快捷键/导航、剪贴板、链接拦截（`_blank`→`_self`、外链开系统浏览器、下载扩展名白名单）、右键菜单、通知/徽标桥
  - `toast.js` — `window.pakeToast` 轻量 toast，供 Rust 侧调下载状态等
- **预设应用**（16 个）：wechat / deepseek / grok / gemini / excalidraw / notion / programmusic / twitter / youtube / chatgpt / flomo / qwerty / lizhi / xiaohongshu / youtubemusic / weread；其中 wechat 带 `incognito: true` + 自定义窗口尺寸

---

# 版本号策略落地

> 2026-08-25
> 产出：[`versioning.md`](./versioning.md)（对应 roadmap 的「规划版号相关的逻辑」，已从 roadmap 删除）

四处版本号之前都是随手定的。定下的判据是「semver 描述这个交付物对它的**消费者**
而言变了什么」，由此四处归属一次分清：**只有各 app 的 `version` 是真号**——它被 `pickUpdate()`
读来决定要不要给用户弹更新提示。`pake_cli` 眼下也是占位：只能
`dart pub global activate --source path` 从本地装，没有分发渠道，没人能选装
哪一版，编号是空仪式，有了渠道再启用。`pake_shell` 构建时被覆盖、
`pake_config` 是 `publish_to: none` 的内部库——同样不维护。**壳不单独编号**：
它是模板不是发布物，想知道某版 app 跑的哪个壳，去看那个 tag 的 commit。

## 摸出来的两件事

**一、`versionCodeFor()` 的输出不是装机的最终值。** 实测三个线上 APK：

| ABI | 偏移 | `1.0.0` 实际 versionCode |
|---|---|---|
| armeabi-v7a | +1000 | 11000 |
| arm64-v8a | +2000 | 12000 |
| x86_64 | +4000 | 14000 |

`--split-per-abi` 让 Flutter 又加了一层 ABI 偏移，而 `config.dart` 的注释和
README 都只说了推导那一步（`1.2.3` → `10203`）。下次有人对着 `aapt dump` 的
数字会以为推导逻辑坏了——两处注释都补上了。

**二、「CI 发的包检测不到更新」不是 bug。** 一开始把它当致命洞，
README 第 108 行早写明是设计使然：`build-presets` 是持续构建通道，
`pakem release` 才是面向用户的发布通道。真实情况是后者从来没走过
（`gh release list` 里没有任何 `<prefix>-v<semver>`），属于「还没发过正式版」。
CI 的 tag 约定不用动。

## 起点重置

三个 preset `1.0.0` → `0.1.0`。更新链路一次都没真正走通过，`0.x` 更诚实。

安全性验证过：线上实际装机的只有 `presets-20260801-153907` 那批，arm64
versionCode 是 **2001**（当时 `buildNumber` 还默认写死 1，2000+1），而 `0.1.0`
推出来是 2100，高于它，能直接覆盖安装。8/23 那几次 CI 构建（12000）没分发给
任何人——这点先跟本人确认过再动的手，否则重置就是让已装用户装不上新包。

## 参照 tw93/Pake：它共用一个号，而那是对的

桌面版兄弟项目走的完全相反：**全仓库一个号** `3.15.7`，同步写在
`package.json`（npm 的 `pake-cli`）、`Cargo.toml`、`tauri.conf.json` 三处；
16 个预打包 app 挂同一条 release，asset 名里连版本号都不带（`ChatGPT.dmg`）。

它能这么做是因为**没有更新检测**（`Cargo.toml` 里 8 个 tauri 插件没有
`updater`，code search 也是 0 命中）——app 版本号没有任何程序在读，只是构建
标记。这边 `pickUpdate()` 拿它做决策，所以必须独立且准确。

有意思的是两边的真号恰好调了个个儿：Pake 的 CLI 有 npm 渠道（真号）、app 号
是空的；这边 CLI 无渠道（空号）、app 号被代码读（真号）。同一条判据
「有没有人或程序依据这个号做决定」，在两个项目里指向相反的结论——这也是
为什么不能照搬。

双通道倒是一致：Pake 的 `continuous`（prerelease 滚动 tag）≈ 这边的
`presets-<时间戳>`，`V3.x.x` ≈ `pakem release`。

---

# 在线构建成为对外入口

> 2026-08-25

`pakem` 本地跑要 Flutter SDK + Android SDK + JDK，这套环境是普通用户打一个包
的主要门槛，而 CLI 本身又没有分发渠道（见 [`versioning.md`](./versioning.md)
里 pake_cli 那节）。参照 tw93/Pake 的四层分发（下载现成包 / 在线构建 / npm 装
CLI / 克隆定制），这边现阶段最现实的是**在线构建**——用户什么都不用装。

`build.yml` 本来就不差：签名回落有警告写进 job summary，产物自动发成 Release
（比 Pake 只给 Artifacts 强，那个 90 天过期），还有个 smoke job 解开 APK 比对
`pake.json` 三个字段。缺的是让人找得到、用得对，所以这轮补的是入口和说明：

- README 加「在线构建」一节：**第一步是 fork**——`workflow_dispatch` 要仓库
  写权限，在别人的仓库里根本看不到 `Run workflow` 按钮，这一步不写用户会卡死
- `build.yml` 补 `icon` / `version` 两个可选输入，空值用 `${VAR:+--flag "$VAR"}`
  整段省掉（实测内层引号有效，带空格的路径不会被拆词）
- `pakem build --json` 输出补 `version` 字段，release notes 从构建结果读版本，
  不在 workflow 里重抄一遍 CLI 的默认值等它腐化

## 两个必须写进文档的行为断点

**一、fork 出来的包不能升级。** fork 里没有签名 secret，回落到 Flutter 的
debug key，而那个 key 每次构建都不一样。后果不是装不上，是装得上但**升不了级**
——第二次构建的包覆盖不了第一次的，只能卸载重装丢数据。给了在自己 fork 里配
三个 secret 的做法。这一条比 Pake 的桌面场景严重：那边 dmg 没签名右键打开就绕过了。

**二、自己构建的包，「检查更新」永远没反应。** `updateRepo` 写死
`sunbird89629/pake_mobile`，而用户的 release 发在自己的 fork 里，两边对不上。
不写明的话这看起来就是个 bug。

构建耗时用的是实测值（`gh run list` 看 build-presets 近六次，都是 4~5 分钟），
冷缓存那次没有数据就只说「明显更久」，不编数字。

## 图标自动发现猜错一次，整个构建失败

在线构建上线后第一次真实使用（`https://www.x.com`）就挂了：

```
{"ok":false,"error":{"message":"Could not decode the icon; expected a PNG, JPEG or WebP image."}}
```

用户根本没指定图标。探针跑出来的真相：

```
discovered: https://www.x.com/apple-touch-icon.png
bytes: 287546
head ascii: <!DOCTYPE html><html dir="ltr" l
```

**x.com 对不存在的路径返回 200 + 首页 HTML，不是 404**——SPA 的 catch-all
路由，很常见。`fetchIconBytes` 只看状态码，把 287KB 的 HTML 当图标交了下去。

真正的缺陷在 `build.dart`：那个 try 只包了**下载**，解码发生在后面的
`materializeConfig` → `writeAndroidIcons` → `_decode`，已经在 try 之外。
所以走的不是 catch 里写着的 `using default`，而是整个构建失败。自动发现
本来就是猜，猜错该回落默认——这是意图和实现对不上，不是新引入的 bug，
只是在线构建把它推到了普通用户面前。

修法是把「能不能解码」纳入自动发现的容错范围（新增 `canDecodeIcon`），
显式 `--icon` 那条路仍然直接抛错——用户指定的东西静默换掉才是掩盖问题。

### 测试顺带挖出第二个缺陷

给 `canDecodeIcon` 写「空字节返回 false」时它没返回 false，而是抛了
`RangeError`：`decodeImage` 探测 magic number 时直接越界，不是返回 null。
原来的 `_decode` 也一样——显式给一个 0 字节文件，用户看到的是解码器内部的
类型错误而不是「这不是一张图」。抽了个 `_tryDecode` 兜住，两条路都走它。

验证没有停在测试上：本地重跑了失败的那条命令，
`Discovered icon is not a usable image, using default.` → 三个 APK 全部出包。
同一次运行还顺带确认了新加的 `version` 字段在真实构建里是 `1.0.0`（CLI 默认值）。

## 图标自动发现的成功率：三个叠在一起的坑

加完 `icon` 字段后顺手探了四个站点，结果一半拿不到图标——而且每个失败的
原因都不一样：

| 站点 | 发现的 URL | 结果 |
|---|---|---|
| github.com | `favicon.svg` | SVG，`package:image` 解不了 |
| x.com | `apple-touch-icon.png` | 200 + 287KB 首页 HTML |
| m.weibo.cn | Google favicon 保底 | ✅ PNG |
| youtube.com | `favicon_144x144.png` | ✅ PNG |

**一、排序逻辑在自伤。** `icon_discovery.dart` 的注释白纸黑字写着「SVG
（`sizes="any"`）维度给 999，在一切非 SVG 之上」——把 SVG 排在最优先，
而下游解不了 SVG。写这行时大概想着矢量图更清晰，没料到解码器不支持。
后果是 GitHub、GitLab 这类挂 SVG favicon 的站点**必然**拿不到图标。
把 `IconTier.svg` 从 order 0 挪到 7（垫底），不删掉是因为真有站点只提供
SVG 时它仍是唯一候选，留着至少能让日志说清「试过了、解不了」。

**二、只赌一个候选没有第二次机会。** 评分是猜的，猜错就回落默认，而队列里
往往还躺着能用的。`discoverIconUrl` 改成 `discoverIconUrls` 返回排序后的
全部候选（`rankedUrls`，去重），build 里逐个试，上限 3 次——每次尝试都是
一趟真实网络请求，墙内每趟都要等超时。

**三、能解码不等于够用。** 修完前两条后 x.com 拿到的是 `favicon.ico`——
32×32，拉到 xxxhdpi 的 192 会糊，而同一条队列再往后一个就是 512×512。
所以判断从「能不能解码」升级成「解出来多大」（`canDecodeIcon` →
`decodedIconSize`，取短边），够 192 就停，不够就继续找更大的。

三条都修完，x.com 的日志变成：

```
Icon: https://www.x.com/apple-touch-icon.png
  not a usable image, trying the next candidate.
Icon: https://www.x.com/favicon.ico
  only 32px, looking for something larger.
Icon: https://abs.twimg.com/.../icon-default-large.png
```

验证到了 APK 里：解包读 launcher icon，确认是 X 的 logo 而不是默认地球仪。
GitHub 那边第一候选直接变成 512×512 的 PNG。

## 补上碰网络那三个函数的测试，捞出一个 Uri.replace 陷阱

`icon_discovery.dart` 原本 14 个用例全是纯函数——`parseLinkIcons`、评分、
`rankedUrls`、`googleFaviconFor`。三个碰网络的
（`parseManifestIcons` / `tryFaviconIco` / `discoverIconUrls`）一个都没测，
而它们签名里都留着 `http.Client?`：那个注入口当初就是为可测加的，测试一直
没写。`discoverIconUrls` 还是刚被改过签名的主入口，改完毫无保护。

用 `package:http/testing.dart` 的 `MockClient` 补齐 8 个用例后，
`tryFaviconIco` 立刻红了：

```
Expected: https://example.com/favicon.ico
Actual:   https://example.com/favicon.ico?x=1#frag
```

**`Uri.replace` 的 `null` 是「保持原样」，不是「清空」。** 所以那句
`pageUri.replace(path: '/favicon.ico', query: null, fragment: null)` 里的后
两个参数**什么也没做**，从带查询串的页面构建出来的 favicon URL 会拖着页面
自己的 query 和 fragment。改成直接 `Uri(...)` 构造。

这个 bug 藏了很久没被发现，正是因为它只在「页面 URL 带 query/fragment」时
才显形，而手工试的站点首页大多是干净的。

新用例锁住的性质，挑值得说的三条：

- **`discoverIconUrls` 永不返回空**——Google favicon 是无条件追加的保底项，
  `build.dart` 的候选循环直接遍历这个返回值，空列表意味着连试都不试。
- **页面抓不到也不炸**——B/C 那层 `catch (_)` 之前没有任何人验证过它真的
  兜住了，现在有一条「页面请求抛异常，D/E 仍走完」。
- **manifest 图标确实合进队列**——GitHub 那个 512×512 就是从 manifest 来的，
  是 SVG 降权后能拿到图标的关键路径。

顺带修了两处被上一轮 tier 重排改成错的注释（`_score` 还写着「SVG 在一切
非 SVG 之上」）。


## 正式包里藏掉设置页的调试项

设置页原本 12 项一视同仁地摆着，其中 URL、User agent、Capture network、
View logs、View requests、Reset to build defaults 六项是开发时用的。普通用户
看不懂，更麻烦的是**前两项按错了这个壳就废了**——把 URL 改成一个打不开的地址
之后，页面是白的，底部栏还在，但唯一能救回来的 Reset 恰好也在这一组里，用户
得先在一堆看不懂的选项里认出它。

开关用 `kShowDebugSettings`（`pake_shell/lib/src/debug_ui.dart`）：

```dart
const kShowDebugSettings = kDebugMode || bool.fromEnvironment('PAKE_DEBUG_UI');
```

选 `kDebugMode` 而不是 Android flavor，是因为两边本来就对齐了：`pakem build`
永远走 `--release`，开发永远是 `flutter run`。flavor 那套要动 build.gradle、
CLI 流水线和 CI 矩阵，换来的是同一条边界。

### 一个 const 是测不出来的

`kShowDebugSettings` 是编译期常量，而 widget 测试永远跑在 debug 模式下——它在
测试里恒为 true，正式包那条路径根本进不去。所以 `DebugDrawer` 上多了一个
`showDebugItems` 参数，默认值就是那个 const，测试显式传 `false`。

新用例里绕了一圈才写对：一开始用 `find.text('Clear cache & cookies')` 断言
「留着」，红了——`ListView` 懒加载，那一项在默认视口下压根没被 build。反过来
更糟：`find.text('View logs')` 的 `findsNothing` 会因为同一个原因**假通过**，
把「没渲染」当成「被藏了」。最后改成直接读 `ListView` 的 children：

```dart
(tester.widget<ListView>(find.byType(ListView)).childrenDelegate
        as SliverChildListDelegate)
    .children
```

问的是「在不在这份列表里」，跟视口无关。顺手加了一条「列表头尾不能是
Divider」——每个调试项都是连着一条分隔线一起藏的，藏错了就会在两端留下一条
悬空的横线。

### 顺带修了错误页的一句谎

`ErrorPage` 在 badUrl 时说的是「The address may be wrong — open settings to
change it.」，而正式包里那个输入框已经不在了。加了 `canEditUrl`（同样默认跟
着 `kShowDebugSettings`），正式包改说「the site may have moved」。「Open
settings」按钮两边都留着——清缓存还在里面。

### 逃生口

包已经装在真机上、要现场看日志或抓包时，`pakem build --debug-ui` 会往
`flutter build` 里加 `--dart-define=PAKE_DEBUG_UI=true`，仍然是 release 构建，
只是把那六项放回去。没有这个 flag 的话，注释里写的那个 define 谁也用不上——
CLI 是唯一的构建入口。


### 真机上才看见的空分组

`pakem build`（永远 release）出包装到 Pixel 上验证，设置页确实只剩四组。但也
立刻看见一个原本被挡着的问题：这个测试 app 没有注入脚本，「Inject scripts」
的标题和那句「toggling a script reloads the page」还在，**底下一个开关都
没有**——而藏掉 URL / UA 之后，这个空分组正好落在页面第一屏最上面。

改成 `scripts.isNotEmpty` 时整组（标题 + 说明 + 分隔线）一起不出现。这个
毛病在 debug 包里一直存在，只是夹在中间没人注意；把上面的东西拿掉，它就成了
进设置页第一眼看到的东西。

三个包依次装到真机上验过：默认 release（四组，无悬空分隔线）、修完空分组的
release、`--debug-ui` 的 release（六项全回来，且仍是 release 签名）。


## 预构建 app 的签名与发布收敛到 CI

原来有两条签名路径，而用户两条都够得着：正式版是笔记本上 `pakem release` 发的
（`~/.pake/signing.properties`），CI 的 `presets-<时间戳>` 用的是
`ANDROID_KEYSTORE_BASE64` secret。两批包 applicationId 相同，**这两张证书一旦
不是同一张**，先从 Releases 页面下过 CI 包的用户再装正式版就是「应用未安装」，
而且没有任何东西核对过它们一致。

收敛的方向不是「加一步核对」，是把其中一条去掉：预设 app 只由 CI 签、只由 CI
发，release key 不放在笔记本上。

### 缺的不是签名能力，是发布路径

`build-presets.yml` 早就会签了。问题在两个 workflow 打的 tag
（`presets-<时间戳>` / `<app>-<时间戳>`）都不参与更新检查——`parseTag()` 只认
`fourkvm-v1.2.0`。所以 CI 出的包用户能下能装，但推不动更新，正式发布只能回到
笔记本上，key 也就必须留在笔记本上。

改成每个 preset 各发一条自己的 release，聚合的 `presets-<时间戳>` 取消。顺带
消掉一处隐患：`_downloadUrl()` 里那段「一条 release 里挂了多个 app 的包，只按
ABI 筛的话 DADATU 用户会拿到 4KVM 的包」的补救逻辑，现在没有输入能触发它了。

### tag 格式不在 YAML 里重写

`<bundleId 末段>-v<version>` 已经在两个地方写着了（CLI 的 `tagFor()` 写、壳的
`parseTag()` 读），YAML 里再抄一遍就是第三处，而写错一个字符的表现是**静默
失效**：包发出去了，没有一个用户收得到。

所以 workflow 直接调 `pakem release`——把 matrix 里那份 preset 原样写成一个
`pake.json` 交给它，tag 它自己推，归档产物它自己找。为此给 CLI 加了两个 flag：

- `--prerelease`：壳的 `pickUpdate()` 跳过 prerelease，所以这是「先放上去只给
  自己装」的实现方式。原来 README 让人事后去 GitHub 界面手动勾。
- `--skip-existing`：先 `gh release view`，查得到就报 `skipped` 退出 0。一次跑
  构建全部三个 preset，多数版本号没动过，「这个版本已经发过了」是常态路径而不
  是错误。

### 签名不对就不发

原来只在 job summary 上留一个 warning，一个 debug key 签的包照样发出去。现在
`androidSigning` 不是 `release` 就直接 fail——这批包是给用户装的，而 debug 签名
的包装不到任何别的构建之上。artifacts 在这一步之前就传完了，失败不影响拿包排查。

### 验证

CI 改动没法靠单测覆盖，所以把两个 step 的 shell 抽出来，用假的 `gh`、假的
`~/.pake/out/` 产物和假的 `build.json` 在本地跑：

- tag 不存在 → `gh release create fourkvm-v0.2.0 … --prerelease`，notes 顶格
  （早期版本用多行字符串拼 notes，行首 10 个空格在 Markdown 里会变成代码块）
- tag 已存在 → 只调了 `gh release view`，summary 写「bump version 才会发布」
- `androidSigning: debug` → exit 1，`::error::` 带出原因

CLI 那两个 flag 有单测（4 条），把实现挖掉验证过会红。


## 抓不到图标就按 app 名生成一个

`4kvm.site` 那个包出来是默认地球仪，查下去发现不是 bug：页面自己声明的
`/ico.png` 是 404，没有 manifest，`/favicon.ico` 也是 404，Google 的 favicon
服务 301 到 gstatic 之后返回 **404 带一个 16×16 的兜底地球仪 body**（CLI 按状态
码正确拒了）。四级候选逐个真的失败。

站点没图标不算罕见，而模板那个默认地球仪装一屏就分不出谁是谁。所以加了第五级：
按 app 名生成。

### 中文名字画不出来

`package:image` 内置的是 Arial 位图字体，只有 ASCII——`影` 在 `font.characters`
里直接查不到。所以字符是逐级找的：名字里第一个 ASCII 字母或数字（`4K影视` →
`4`），一个都没有就用 bundleId 末段的（`com.pake.dadatu` → `D`）。bundleId 永远
是 ASCII，这条链一定能落地。

### 48px 位图字体放大到 512

`arial48` 的字形高度只有 35px，放大 6 倍边缘是一格一格的台阶，而且 Arial 常规体
的笔画搁在图标上偏细。试过三种：

- 最近邻直接放大：台阶明显
- cubic 插值：更糊，最差
- **最近邻放大 → 高斯模糊 → 按透明度阈值切回硬边**：台阶被抹平，阈值取得比
  半透明中点低（70/255），顺带把笔画撑粗一点

第三种明显最好。模糊前要四周留白，否则撑出去的部分被边界裁掉。

字形定位不算基线和 `yOffset`：画在透明画布上再按透明度 `findTrim`，拿到的就是
字形自己的包围盒，`4` 和 `Y` 的度量差别不用管。宽字符（W、M）按高度缩会顶到
左右边，所以再按宽度收一次。

颜色是自己算的 FNV-1a 哈希取模一个八色盘，没用 `String.hashCode`——那个值不保证
跨运行稳定，否则同一个 app 每次重新构建都可能换个颜色，用户会以为装错了。

### 验证

10 条单测（字符挑选 5 条、生成 5 条，含「同样输入同样字节」和「宽字符不出血」）。
真出了一个包：`icon: generated`，从 workspace 里掏出
`mipmap-xxxhdpi/ic_launcher.png` 看，192×192 的蓝底白「4」，就是桌面上会显示的
那张。


## 分享当前页

影视站这类内容是拿来传的，看到一部片想丢给朋友，之前只能截图。

### 先决定的是位置，不是分享本身

分享逻辑就是调一次 `share_plus`，真正要定的是入口放哪。roadmap 上排在同一个
位置的还有两条（复制当前 URL、用外部浏览器打开），底部栏当时是钉死的 208 宽、
三个 56 的触控格 + 四个 10 的间隙，一条一条往里加按钮撑不住。

第四格给了「更多」（⋯），点开一个底部弹层，Share 是里面第一条。栏宽 208→274。
**按钮数就封在四个**：第五个是 340，在 360dp 的窄屏上只剩 10 的余量，那已经不像
一块浮在网页上的胶囊了。所以后面两条直接进菜单，不再回来讨论位置。

弹层而不是锚在按钮上的 `showMenu`：入口本来就贴着屏幕底边，弹层正好出现在拇指
底下，`showMenu` 的浮层会往屏幕中间飘。

### 分享的是当前页，不是首页

`config.url` 是构建时那个首页地址。逛到第三层想丢给朋友的是那一页，所以点开菜单
时现问一次 WebView（`getUrl()` / `getTitle()`），没有缓存一份跟着导航更新——
`onUpdateVisitedHistory` 已经够频了，再挂一份状态就多一个要同步的副本。

### 正文是「标题 + 换行 + URL」

Android 上标题本该走 `EXTRA_SUBJECT`（Chrome 就是这么发的），但真去读它的接收方
很少，微信、QQ 这类只取 `EXTRA_TEXT`。只发 URL 的话对面收到一条光秃秃的链接，
看不出是哪部片。所以标题也拼进正文，`subject` 照样带上，读它的那些 app 白赚。

两种情况只发 URL：标题为空（页面还没解析出 `<title>`，`getTitle()` 返回 null），
以及标题就等于这个 URL（站点不给 `<title>` 时 WebView 会把地址当标题返回）——
后者不判就成了同一条链接连发两遍。

### 验证

7 条单测：`shareTextFor` 四条（正常、无标题、标题即 URL、trim），菜单两条
（选中返回 `MoreAction.share`、点遮罩返回 null），底部栏一条新的——把栏宽写到
340 验证过它会红，360dp 窄屏那条断言是真的在拦人。

真机：装 ShareCheck 到 Pixel，从 4kvm 深逛一页点 ⋯ → Share，系统面板出来的是
当前那一页的标题和地址，不是首页。


## 分享的应该是 app 本身，不是当前页

上一节做的是「分享当前页」——真机面板弹出来是 4kvm 站点那一页的标题和
`www.4kvm.tv` 地址。对着真面板一看就明白了：朋友收到这条链接，打开的是
网页，装不了壳。口口相传分享的是 app：影视站这类没有应用市场，装机渠道
就是「朋友发给朋友」。

### 换成什么

- **内容**：app 名 + 一句话介绍 + 本版本 release 页地址。介绍来自构建期
  配置新增的 `description` 字段（`pakem build --description` 或 preset 的
  json），三个 preset 各写了一句——分享出去的每条消息都说得清「这是什么、
  能干什么」。
- **链接**：`releasePageUrl()` 离线拼 `<bundleId 末段>-v<version>` 的 tag，
  指向 release 页而不是 APK 直链。一条 release 挂三个 ABI 的包，直链钉死
  一个（通常 arm64）发到别的设备就是「应用未安装」；release 页让人按设备
  自己挑。
- **壳里的 tag 格式又出现了一处**：CLI 的 `tagFor()` 写、`parseTag()` 读，
  现在 `releasePageUrl()` 拼。它按 `parseTag` 承认的那一个规则拼（bundleId
  末段 + `-v` + 版本），注释里写明真相源在 CLI，改格式要两边一起改。

`--description` 走的是现有的 `PakeFlags` / `mergeConfig` 通道（pake.json →
壳的 `buildTime`），和 name、version 一个待遇，没有为它单开一条路径。

## 预设 app 的真机截图进 README

README「预构建 App」那节最早是三行表格，没有图。表格写得出「干什么」，
写不出「装完长什么样」——对还没装的人来说，一张真机截图比「4K 高清影视」
五个字有说服力得多。

### 截的是「当前正式版」，不是手机里躺着的那份

版本 bump 后旧图就失真了：表格链到 `fourkvm-v0.2.0`，图还是 v0.1.0 的
首屏，两边对不上，比没图更糟。所以流程第一步是下载最新正式版 APK
（`gh release download <tag> --pattern '*arm64-v8a*'`）重新装到真机，
而不是直接截手机上已经装着的旧包。

这事值得固化成 skill：查 tag、下载、装、等加载、截、验证、缩放、核对
README 版本号，八步漏一步就出废图，而且版本每次 bump 都要重来一遍。
`.claude/skills/app-screenshot/` 把它写成可触发的话术，以后喊一句
「更新 README 里的截图」就跑完。

### 真机 + 缩到 400px

真机才截得出真实形态——模拟器的分辨率、字体、WebView 渲染都和 Pixel 有
差。固定用 Pixel（`39111FDJH00D47`），无线别名 `_adb-tls-connect` 结尾的
一律不用。

不存全尺寸：手机截图 1080×2400，放 README 一张就占一屏，三个 app 三屏
没人往下翻。`sips --resampleWidth 400` 缩到 400px 宽，三个 app 一行并排
刚好。

### 两个「停下等人」而不是硬扛的地方

- **锁屏就停**，让用户解锁，绝不猜 PIN——之前有过设备锁屏导致截屏全黑。
- **临时区只放 `/tmp/app-screenshot/`**，不碰 `~/.pake/out/`——那下面的
  构建产物用户明确说过不清。

截完每张图先验证非空白（`sips` 看像素，几 KB 或纯色就是没截好），再
同名覆盖 `docs/images/<slug>.png`——README 里已引用的 markdown 不用动。

### 验证

README 进了 5 张图：预设 app ×3（4KVM / DADATU / YouTube，一行并排）、
图案锁、Run workflow 表单。三个预设 app 各自从最新正式版 APK 截出，
截图内容与表格「干什么」的描述对得上。

## 内置去广告样式注入

roadmap 里的「去广告」写的是「加一个内置 `adblock.css` 即可」，真做起来
确实就一件事：写 CSS。注入脚本体系、`enabledScripts` 开关、设置页 toggle
全是现成的，`adblock.css` 一进 `injectScripts` 就物化成 id `adblock`，
默认全开、误伤了随时关——零改动衔接。

### 宁漏勿误，不碰 YouTube

CSS 拦不了 YouTube 的视频前贴片（那是播放器里插的，不是页面上的广告节点），
硬套通用广告选择器反而可能把 YouTube 的正常布局一起藏了。所以 `adblock.css`
只接 4kvm / dadatu 两个影视站，选择器也收得很窄：`ad-`/`ads-` 前缀、
`-ad-`/`_ad_` 包裹、`advert`、广告网络 iframe、悬浮/贴片位，最弱的
`#ad`/`.ad` 放最后。宁可漏杀，不误杀——广告没藏掉是体验问题，正常内容被
藏了用户只会卸载。

### CI 的路径坑：build 不在仓库根跑

preset 里 `injectScripts: ["presets/adblock.css"]` 是相对仓库根的路径，但
`build-presets.yml` 的 build 步骤 `working-directory` 在 `packages/pake_cli`，
`validateConfig` 和物化都按 cwd 解析，相对路径会找错地方。解法是矩阵投影里
带上 `injectScripts`，build 步骤前缀 `$GITHUB_WORKSPACE` 换成绝对路径再交给
`--inject`——不把 build 挪出 `packages/pake_cli`，改动最小。

### 预设校验提前到单测

`presets/*.json` 在 pake_cli 的上级目录，`dart test` 从不把它当代码走一遍，
路径写错、脚本 id 撞车、json 拼错都只会在 build-presets 真跑时炸，反馈太晚。
`pake_cli/test/presets_test.dart` 把「name/url/bundleId 齐全、脚本路径存在且
非空、id 不撞车」提到单测，坏掉在 PR 阶段就拦下。

### 验证

`dart analyze` 无告警；pake_cli 全量 170 项通过（含新增 7 项预设校验）。
真实物化 dry-run：`presets/adblock.css` 走 `materializeScriptsInto` 后
`index.json` 里是 `{id: adblock, kind: css}`，注入为 `<style>`；`4kvm` /
`dadatu` 两个预设的 `defaultEnabledScripts` 都含 `adblock`。
