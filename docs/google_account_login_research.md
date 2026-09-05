# Google 账号登录调研

YouTube 预设壳基于 WebView 展示 `youtube.com`。用户如果想要"登录态"（订阅、点赞、
收藏这些需要账号的网页交互），有没有办法让 Google 登录在这个 WebView 里正常跑起来？
调研了两条路，结论都不完美，但落地方案是明确的。中途一次真机实测的结果跟最初的
结论对不上，顺着查下去，发现 Google 其实是两套不同的拦截机制，作用的登录入口
也不一样——这才是关键，见下面「两种检测机制」一节。

## 结论先行

- **Google 对"内嵌 WebView"的拦截不是铁板一块的一刀切**——分两套机制，一套是
  写死的硬拦截（只管 OAuth 授权端点），一套是启发式风控提示（管普通登录页），
  YouTube 预设的登录走的是后者，**不保证必然触发**，真机实测能用账号密码登录
  成功属于正常情况，不代表这条路线稳定
- **把 UA 换成标准 Chrome UA（`RuntimeKeys.userAgent` 里已有的 `Android Chrome`
  预设）能进一步降低触发风控提示的概率**——但这终究是绕过 Google 官方限制的
  做法，长期稳定性没有保证
- **OAuth token 方案（Custom Tabs 走系统浏览器授权）走不通**——能拿到 API token，
  但换不来"网页显示已登录"这个效果，对 WebView 内容本身没有帮助

## 两种检测机制

一次真机测试发现：YouTube 预设**默认打包、没有手动切换过 UA**，账号密码
登录能走通。这跟"默认会被拦截"的最初判断对不上，查下去才发现 Google 其实分了
两套完全不同的机制，作用的登录入口不一样：

| | 机制一：OAuth 授权端点硬拦截 | 机制二：登录页风控提示 |
|---|---|---|
| 拦的是哪个入口 | `accounts.google.com/o/oauth2/auth`（走 Authorization Code 流程，比如第三方网站的"Sign in with Google"按钮） | `accounts.google.com/ServiceLogin` 等常规登录表单（YouTube 网页版走的是这条） |
| 判定方式 | UA 字符串匹配已知内嵌浏览器特征库，命中即拒 | 综合风控评分：账号历史、登录环境、浏览器能力探测等，UA 只是信号之一 |
| 是否必然触发 | **是**——2016 年公布、2021 年强制、2023 年 7 月起对所有开发者生效，返回 `disallowed_useragent`，写死的策略 | **否**——启发式判断，同一个默认 WebView UA，不同账号/环境下结果可能不同 |
| 报错文案 | `disallowed_useragent` | "This browser or app may not be secure" |

YouTube 预设壳只是展示 `youtube.com` 网页版，用户点登录走的是常规登录表单，
命中的是机制二——本来就不保证每次都拦，这解释了真机测试能用账号密码登录成功，
不代表这条路线长期稳定，只代表这次没被判定为"可疑"。

参考：[Google Developers Blog](https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/)、
[Auth0 的分析](https://auth0.com/blog/google-blocks-oauth-requests-from-embedded-browsers/)

## Google 怎么识别"内嵌 WebView"

- **UA 字符串匹配已知特征库**——不只是 Android WebView 默认带的 `; wv` token
  （Android 16 的 UA 精简计划特意保留了这个 token，就是为了让网站还能识别出
  WebView），Google 还维护一份已知内嵌浏览器 UA 签名清单（Chromium Embedded
  Framework、Facebook/Twitter/Instagram 站内浏览器等）
- **`X-Requested-With` header**——WebView 曾经会自动在所有请求上带这个 header，
  值是宿主 app 的包名，等于主动告诉服务器"我是被谁嵌进去的"。Android WebView
  从 v103 起把这个行为改成 **opt-in**（`WebSettingsCompat.
  setRequestedWithHeaderOriginAllowList`），默认不发。对现在新开发的 app 来说，
  这条信号默认就是关的，不用额外处理，但也别手滑主动开
  ——[Android Developers Blog](https://android-developers.googleblog.com/2023/02/improving-user-privacy-by-requiring-opt-in-to-send-x-requested-wih-header-from-webview.html)

### 为什么第三方浏览器（Firefox/Edge/UC 浏览器）不受机制一影响

Google 分辨的不是"是不是第三方"，是"是不是一个独立浏览器 app"：

- 这些浏览器是用户主动装的独立产品，不是嵌在别的 app 界面里的组件
- UA 自报家门（`Firefox/`、`EdgA/`、`UCBrowser/`），不带 `wv`，也不命中已知
  特征库——UC 浏览器这类"套壳 WebView 的浏览器"其实也做了"改 UA 伪装"这件事，
  只是这个操作是浏览器厂商自己做的，做完就是一个独立浏览器
- 有自己独立的进程和 cookie jar，不受宿主 app 控制或篡改——这正是 Google
  拦截内嵌 WebView 的初衷

## 路径一：改 UA 伪装成 Chrome（能落地，但是绕过手段）

把 WebView 的 UA 换成不带 `wv` 标记的标准移动端 Chrome UA 后：

- 能进一步降低命中机制二风控提示的概率，正常情况下可以完整走完账号密码登录
  （含两步验证）
- 但 Google 的风控不止查 UA，登录环境被判定"可疑"时，触发手机验证码/异常登录
  提醒的概率比真 Chrome 里登录更高
- 这条路是绕过 Google 明文禁止的限制，随时可能因为新的检测手段（不止查 UA，
  比如行为特征、缺失的浏览器能力）而失效——今天能用不代表这个 apk 版本一直能用

`packages/pake_config/lib/src/runtime_keys.dart` 里已经有现成的 UA 预设可用：

```dart
static const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
```

如果 YouTube 预设要支持登录，这是唯一能让"网页登录态"生效、且能进一步降低
风控命中率的路子。

## 路径二：Custom Tabs + OAuth（标准做法，但解决的是另一个问题）

Google 官方推荐、认可的移动端登录方式是 **Chrome Custom Tabs + Authorization Code +
PKCE**：

1. app 用 Custom Tabs（不是 WebView）打开 Google 授权页——Custom Tabs 复用系统里
   已装浏览器（Chrome 或其他支持 Custom Tabs 协议的浏览器）的真实进程，Google
   认得出不是嵌入式 WebView，不会拦
2. 用户在浏览器里登录、同意授权
3. Google 跳转到注册好的 `redirect_uri`（自定义 scheme 或 App Link）
4. 系统 Intent Filter 把跳转路由回 app，带回授权码
5. app 拿授权码换 `access_token` / `id_token`（公开客户端配 PKCE）

这条路 Android/iOS 都有官方支持（`androidx.browser` Custom Tabs、iOS
`ASWebAuthenticationSession`），不是 hack。**但它解决的是另一个问题**：

- 换到的是 **OAuth token**，能用来调 Google API（比如 YouTube Data API）
- 不是浏览器的 session cookie。登录态 cookie（SID/HSID 那组）是 `HttpOnly`，页面 JS
  读不到，更没有 API 能把它导出、注入进 WebView 的 cookie store
- 所以这条路换不来"WebView 里的 youtube.com 显示已登录"——这正是 YouTube 预设壳
  想要的效果，而这一步 Google 没有开放接口

### 为什么"借道 Chrome 再传回来"这个思路走不通

理论上还想过："能不能在 Chrome 里登录，再想办法把结果传回 app？"——不行，卡在
**回传**这一步：

- app 和浏览器之间唯一的回传通道是深链（跳转 URL → app 的 intent-filter 截获）
- YouTube 的 OAuth `redirect_uri` 由 Google 侧 client 配置写死，指向
  `youtube.com`，我们没有注册过这个 client，改不动
- 就算能截到 `youtube.com` 的 App Link（也做不到——App Links 要 YouTube 自己的
  `assetlinks.json` 认证），截到的也只是登录完成后的页面 URL，里面不含登录态本身
- 如果是**自己的**站点（自己注册 OAuth client、能配 `redirect_uri`），这个模式完全
  可行，但换到的是自己 client 的 token，不是浏览器会话，YouTube 网页不会认

## 落地建议

YouTube 预设要不要支持登录，取决于用途：

| 需求 | 方案 | 可行性 |
|---|---|---|
| 网页本身显示已登录（订阅/点赞/收藏这类交互） | 走机制二默认能用，改 UA 伪装 Chrome 能降低风控概率 | 能用，但不保证长期稳定 |
| 调用 YouTube API 读写数据 | Custom Tabs + OAuth token | 官方标准方案，稳定可靠 |

两者不能互相替代——如果目标是前者，只有"默认 + 可选改 UA"这一条路可选。

## 扩展：如果要自己开发一个支持 Google OAuth 的浏览器 app

跟 YouTube 预设这种"套壳展示单一网站"不同，如果目标是做一个通用浏览器（用户
在里面自由上网，某个网站弹出"Sign in with Google"要能正常走完，即命中机制一），
需要做的事情不一样，且要先分清楚是哪种需求：

- **场景 A**：浏览器里的网页要跳"用 Google 登录"——需要让 Google 把这个浏览器
  判定为独立浏览器而非内嵌 WebView，见下
- **场景 B**：浏览器 app 自己要拿 Google API token（比如"登录浏览器账号同步
  书签"）——不该走 WebView，直接用 Custom Tabs + AppAuth（`net.openid:appauth`），
  等同路径二，不需要考虑"是不是浏览器"这个问题

### 场景 A 的具体做法

1. **UA 自报家门**——用 `WebSettings.setUserAgentString()` 换掉默认带 `wv` 的 UA，
   换成不含 `wv`、理想情况下带自己产品标识的 UA（Edge 用 `EdgA/`，Opera 用
   `OPR/`，Brave 保留纯 Chrome UA）
2. **`X-Requested-With` header 保持默认不发**——Android WebView v103+ 起默认
   opt-in 关闭，不用额外处理，别手滑调用
   `setRequestedWithHeaderOriginAllowList` 主动开
3. **别在 Google 域名上做 JS 注入、网络拦截、`addJavascriptInterface`**——这类
   操作本身是内嵌 WebView 最典型的风险特征，也是真实的安全隐患
4. **具备完整现代浏览器能力**：WebAuthn/FIDO2、Service Worker、标准 Cookie
   管理——风控用这些判断"是不是一个功能健全的独立浏览器"
5. **没有官方白名单可申请**——Google 不提供"认证成为可信浏览器"的注册渠道，
   纯粹是它单方面的 UA 特征库 + 行为风控黑盒判断，做到上面几条能降低命中率，
   不是 100% 保证

### 引擎选型：System WebView 还是自带完整引擎

这是决定"能不能长期稳定过检测"的根本因素：

| | 套壳 System WebView | 自带完整引擎（Chromium 全量构建 / GeckoView） |
|---|---|---|
| 代表产品 | Via Browser 等轻量 Android 浏览器 | Brave/Edge/Opera（Chromium）、Firefox（Gecko） |
| 包体积/开发成本 | 小，几百 KB，一个人能做 | 大，上百 MB，需要跟 upstream 走独立发布节奏 |
| 安全更新 | 跟随系统 WebView 自动更新 | 自己维护更新链路 |
| 过检测的结构性保证 | 无——底层 JS 引擎指纹、渲染能力集合跟系统里所有其他
  用 WebView 的 app 完全一样，即使 UA 换了也只是表层信号 | 有——完全独立的进程和引擎实例，从 Google 检测视角看跟"真的 Chrome"没有结构性差异 |

除非产品定位就是要做一个严肃的、大规模用户的浏览器产品，否则不值得为了"多一点
确定性"去啃自带引擎这块硬骨头——先用 System WebView + 上面几条卫生做法，这也
是行业里大多数轻量浏览器实际在走的路。要不要换引擎可以留到产品验证之后再决定，
两条路在应用层 API 形态上差别巨大，换引擎基本等于重写渲染层，不是能中途小改
的事。
