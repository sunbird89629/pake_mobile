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
