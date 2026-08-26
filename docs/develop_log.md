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
