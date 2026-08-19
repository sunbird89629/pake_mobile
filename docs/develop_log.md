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

## 四、值得借鉴的（按价值排序）

### 高价值 · 直接能落地

**1. 外部链接策略（forceInternalNavigation + safeDomain）**
- Pake 默认拦截 `_blank`、把外链丢给系统浏览器，支持 `--safe-domain` 白名单（SSO 回调域名留在壳内）
- pake_mobile 现在对链接点击基本不管，外链会直接跑出壳
- 建议：config 加 `safeDomains` 字段 + 拦截逻辑，站内链接壳内开、外部域名系统浏览器开
- 对 4kvm（视频站外链多）是实打实的体验提升

**2. 网页通知 → 系统通知桥（event.js 的 Notification 桥）**
- Pake 用 `Object.defineProperty` 把 `window.Notification` 换成调用原生命令的封装；还桥了 `setAppBadge`（角标）
- 移动端可用 `local_notifications` 插件，在注入脚本里包一层 `Notification` 发到原生
- YouTube/4kvm 的站内推送就能弹系统通知

**3. 页内查找（enableFind）**
- Pake 的 `find.js` 实现了 Cmd/Ctrl+F 查找 UI（`text.find`）
- flutter_inappwebview 自带 `findAll()`/`findNext()`，底部栏加查找入口即可
- 对长文站点很实用

**4. 去广告样式注入（style.js 的思路）**
- Pake 用 `display:none !important` 批量隐藏广告 DOM，且按站点维护
- 咱们已有注入脚本体系，加一个内置 `adblock.css` 脚本即可，与现有 `enabledScripts` 开关无缝衔接

**5. 回主页按钮 + 复制当前 URL**
- Pake 有 `⌘⇧H` 回主页、`⌘L` 复制 URL
- 底部栏加 home 按钮（现在刷新=reload，用户深逛后想回入口还得手动）；debug drawer 加「复制当前 URL」

### 中价值 · 做开关型功能

**6. 无痕模式（incognito）** — 不持久化 cookie/存储；对 4kvm 这类登录态敏感的站点有用

**7. 强制深色模式（darkMode）** — 注入 CSS 反色，实现简单（一个脚本的事）

**8. 清除缓存并重启** — debug drawer 加一个按钮，排查站点问题时不用重装

**9. 页面缩放（zoom）** — Pake 缩放走原生 WebView 而非 CSS hack；flutter_inappwebview 支持 `setTextZoom`，做成设置项

**10. CLI 的 `--json` + `--config`** — `pakem` 目前输出偏人读；schema 可参考 Pake 的 `pake.schema.json` 结构

### 低价值 / 移动端不适用

- 系统托盘、关窗隐藏、激活快捷键、多实例/多窗口、多架构、安装器语言 —— 桌面概念
- 代理、忽略证书错误 —— 4kvm 场景代理方向不合规；忽略证书是安全风险，不做
- wasm 支持 —— 移动端 WebView 已原生支持
- 拖拽上传 —— 移动端几乎无拖拽场景

## 五、额外建议

Pake 的 `default_app_list.json`（16 个预设 + 每个可带 `incognito`/宽高等个性化配置）值得借鉴进 preset 体系：现在 preset 只有 `{name, url, bundleId}` 三件套，可扩展成「每个预设可携带默认脚本集合、默认 UA、无痕开关」。

## 六、Pake 内部结构参考

- **注入脚本** `src-tauri/src/inject/`：auth.js / custom.js / event.js / find.js / fullscreen.js / style.js / theme_refresh.js / toast.js
- **Rust 命令层** `src-tauri/src/app/`：cert.rs / config.rs / invoke.rs / menu.rs / navigation.rs / setup.rs / window.rs
- **关键注入脚本职责**：
  - `style.js` — 去广告 CSS + 沉浸式头部适配（无标题栏时给各站点头部加 padding-top，非 mac 顶部加 20px 可拖拽条）
  - `event.js` — 快捷键/导航、剪贴板、链接拦截（`_blank`→`_self`、外链开系统浏览器、下载扩展名白名单）、右键菜单、通知/徽标桥
  - `toast.js` — `window.pakeToast` 轻量 toast，供 Rust 侧调下载状态等
- **预设应用**（16 个）：wechat / deepseek / grok / gemini / excalidraw / notion / programmusic / twitter / youtube / chatgpt / flomo / qwerty / lizhi / xiaohongshu / youtubemusic / weread；其中 wechat 带 `incognito: true` + 自定义窗口尺寸
