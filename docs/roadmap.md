# Roadmap

想做但还没做的功能点。**只记「做什么 + 为什么值得做 + 怎么做」，不填日期、不排 P0/P1**——
排期一旦写下就开始腐化，而理由不会。

一条做完了就挪到 "已完成"，并在 `docs/develop_log.md` 记一笔落地过程；
想清楚不做了就挪到「不做」，写明理由，免得下次再讨论一遍。

## 近期

- **外部链接策略**（`safeDomains`）
  现在链接点击基本不管，外链直接跑出壳。config 加 `safeDomains` 字段 + 拦截逻辑：
  站内壳内开、外域丢系统浏览器。对 4kvm 这种外链多的站是实打实的体验提升。

- **为预设 App 添加介绍视频**
  给每个预设 App 配一段介绍视频 URL（或本地路径），在 App 详情页或应用市场页展示。

- **回主页按钮 + 复制当前 URL**
  刷新 = reload，深逛之后想回入口只能手动。两条都进底部栏的「更多」菜单（分享那条已经把
  菜单和「读当前页 URL」都做出来了，这里是往里加行）。

- **用外部浏览器打开当前页**
  壳里做不了的事总有几件：Google 登录在 embedded WebView 里被直接拒（调研见
  [`google_account_login_research.md`](./google_account_login_research.md)）、某些下载和
  支付跳转、以及排查「到底是壳的问题还是站点的问题」时想拿真浏览器对一眼。
  `url_launcher` 的 `launchUrl(mode: LaunchMode.externalApplication)` 一行的事，入口进
  底部栏的「更多」菜单，和「复制当前 URL」那条挨着做正好。

  说明白一件事：**登录态带不过去**（壳和系统浏览器不共享 cookie），所以它是逃生口，
  不是常规路径。和 `safeDomains` 那条的区别也在这儿——那个是外域自动丢出去，这个是
  用户对当前页主动这么做。

## 以后

- **页内查找**
  `flutter_inappwebview` 自带 `findAll()` / `findNext()`。移动端用得少——触屏长页里定位
  文字不如直接搜，入口也不好放；等以后做 PC 端时再加，键盘 Ctrl+F 在桌面是刚需。

- **网页通知 → 系统通知桥**
  注入脚本里用 `Object.defineProperty` 换掉 `window.Notification`，经 `local_notifications` 发到原生。

- **打包本地 HTML**
  AI 让写本地 HTML 越来越简单，但部署服务器对普通用户仍有门槛。打包成 App 安装到手机即可使用，体验流畅。
  在打包流程中支持选择本地文件夹或 zip，WebView 加载本地资源（file:// 或 assets 方式），无需公网服务器。

- **强制深色模式**：注入一个反色 CSS，一个脚本的事。

- **清除缓存并重启**：debug drawer 加一个按钮，排查站点问题时不用重装。

- **页面缩放**：`setTextZoom` 走原生而非 CSS hack，做成设置项。

- **preset 携带更多默认值**
  现在 preset 只有 `{name, url, bundleId}`。可扩展成每个预设自带默认脚本集合、默认 UA、无痕开关。

- **CLI `--json` 输出**：`pakem` 现在的输出偏人读，机器读需要结构化。

- **探索 Android TV 盒子支持**
  很多网站没有 TV 版 App，电视上只能靠投屏。Pake 打包成 TV 版 App 可直接在电视/盒子上浏览。
  调研 Android TV 构建要求（leanback launcher、`LEANBACK_LAUNCHER` category、TV banner 图标、
  `uses-feature android.software.leanback`）。

  **核心难点是遥控器交互**：TV 无触摸屏，一切靠遥控器的 DPAD 方向键 + 中心键（OK）+ 返回键。
  而网页是为鼠标/触控设计的，没有「焦点」概念——方向键按下去网页不知道往哪移。
  需要：注入脚本模拟焦点导航（DPAD 在可点击元素间移动 + 高亮当前焦点，OK 触发 click、
  方向键滚动页面），处理返回键路由（先退焦点/弹层，再退网页历史），以及遥控器文字输入
  （屏幕键盘、避开 input 焦点陷阱）。调研 `flutter_inappwebview` 在 TV 上的 key event /
  focus / 滚动行为能否支撑，还是需要原生 TV 层做焦点管理。

- **内置视频播放器**（参考 Soul Browser）
  4kvm、dadatu 这类影视站就是这个壳的主要用途，而网页播放器在移动端普遍难用：控件小、
  手势基本没有、全屏行为看站点脸色、倍速和进度记忆更是没影。把播放这一段从网页手里接过来
  是这几个 app 体验上最大的一块。

  做法分两步：**嗅探**——注入脚本 hook `<video>` 的 src 变化，或用 `shouldInterceptRequest`
  抓 m3u8/mp4 直链；**播放**——`media_kit`（libmpv，HLS/倍速/字幕都齐）或 `video_player`
  （ExoPlayer）。嗅到链接后弹一个「用内置播放器打开」的入口，不抢网页自己的播放。

  手势照抄用户已经会的那套（YouTube／B 站基本一致，移动端没有快捷键，对应的是手势）：
  中间双击播放/暂停、左右两侧双击 ±10s、横向拖动 seek 并显示目标时间、左侧竖滑亮度、
  右侧竖滑音量、长按 2× 倍速、单击显隐控件。

  已知难点：直链多半带防盗链，得把 WebView 的 cookie、UA、Referer 一起带给播放器；
  加密流（DRM、自定义 key）嗅到了也放不了，要能干净地退回网页播放器而不是卡在黑屏。

## 不做

- 系统托盘、关窗隐藏、全局快捷键、多窗口/多实例、多架构 —— 桌面概念，移动端不成立。
- 代理 —— 域名封锁换域名就解决，走代理方向不合规也不划算。
- 忽略证书错误 —— 安全风险。
- 拖拽上传 —— 移动端几乎没有拖拽场景。
- **远程配置/脚本热更**：注入脚本、`safeDomains`、UA 从远端拉，不重装 APK 就生效。
  技术上成立，但会引入第二个版本号轴（配置版本独立于 app 版本），而这个壳的配置
  改动频率根本撑不起那套机制。版本号策略见 [`versioning.md`](./versioning.md)。

- **无痕模式**：已有 App Lock（防设备他人窥屏）和 Clear cache（一键清空 cookie/存储），不持久化需求可由这两者组合满足。而且 Pake 是单网址打包，不是通用浏览器，「无痕」是浏览器语义，套到单站 App 上反而会让用户困惑。

## 已完成

- **正式环境隐藏不必要的设置项**（2026-08-26）
  URL、User agent、Capture network、View logs、View requests、Reset to build defaults
  只在 debug 构建里显示，开关是 `kShowDebugSettings`；正式包的逃生口是
  `pakem build --debug-ui`。落地过程见 [`develop_log.md`](./develop_log.md)。

- **预构建 app 的签名与发布收敛到 CI**（2026-08-26）
  `build-presets.yml` 现在每个 preset 各发一条 `<bundleId 末段>-v<version>` 的
  pre-release（直接调 `pakem release`，tag 格式不在 YAML 里重写），验过再取消
  勾选转正；签名不是 release 就直接失败。落地过程见
  [`develop_log.md`](./develop_log.md)。

- **分享 app 本身**（2026-08-29）
  底部栏第四格是「更多」（⋯），弹层里第一条是 Share app，走 `share_plus` 发这个
  app 的**名字 + 介绍（构建期配置的 `description`）+ 本版本 release 页地址**。
  栏宽 208→274，四个按钮到此封顶，后面排队的「复制当前 URL」「用外部浏览器打开」
  直接进这个菜单。反向的「别的 app 分享链接进来打开」不做——单站壳收到任意链接
  没地方放。落地过程见 [`develop_log.md`](./develop_log.md)。

- **为预设 App 添加真机截图（图片介绍）**（2026-08-31）
  README「预构建 App」一节给 4KVM / DADATU / YouTube 各配一张真机截图，由
  `app-screenshot` skill 从最新正式版 APK 一键截图、缩放后存 `docs/images/`。
  落地过程见 [`develop_log.md`](./develop_log.md)。

- **调研 Google 登录的对接**（2026-09-05）
  结论：Google 对嵌入式 WebView 分两套拦截——OAuth 授权端点是硬拦截（必然拒绝），
  普通登录页是风控启发式（改 UA 只是绕过、不稳）；Custom Tabs 能拿到 API token 但
  换不来 WebView 里的「已登录」。落地方向是「用外部浏览器打开当前页」当逃生口，并
  把注入脚本限定到站点自己的 origin（不沾登录页）。
  完整调研见 [`google_account_login_research.md`](./google_account_login_research.md)。

- **去广告样式注入**（2026-09-06）
  新增内置 `presets/adblock.css`——按常见广告容器的命名规律整段隐藏（`ad-`/`ads-` 前缀、
  `-ad-`/`_ad_` 包裹、`advert`、广告网络 iframe、悬浮/贴片位、`#ad`/`.ad`），原则
  宁漏勿误。接入 4kvm / dadatu 两个影视站预设，走现有 `enabledScripts` 开关无缝衔接
  （默认开、可在设置页关）；YouTube 不接——视频前贴片 CSS 挡不住，硬上反而可能误伤
  布局。落地过程见 [`develop_log.md`](./develop_log.md)。
