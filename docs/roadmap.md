# Roadmap

想做但还没做的功能点。**只记「做什么 + 为什么值得做 + 怎么做」，不填日期、不排 P0/P1**——
排期一旦写下就开始腐化，而理由不会。

一条做完了就删掉（git 历史里有），并在 `docs/develop_log.md` 记一笔落地过程；
想清楚不做了就挪到「不做」，写明理由，免得下次再讨论一遍。

来源：`docs/develop_log.md` 的 Pake 功能分析（2026-08-19）。

## 近期

- **外部链接策略**（`safeDomains`）
  现在链接点击基本不管，外链直接跑出壳。config 加 `safeDomains` 字段 + 拦截逻辑：
  站内壳内开、外域丢系统浏览器。对 4kvm 这种外链多的站是实打实的体验提升。

- **回主页按钮 + 复制当前 URL**
  刷新 = reload，深逛之后想回入口只能手动。底部栏加 home；debug drawer 加「复制当前 URL」。

- **去广告样式注入**
  已有注入脚本体系，加一个内置 `adblock.css` 即可，和现有 `enabledScripts` 开关无缝衔接。

- **页内查找**
  `flutter_inappwebview` 自带 `findAll()` / `findNext()`，底部栏加入口就行。长文站点实用。

## 以后

- **网页通知 → 系统通知桥**
  注入脚本里用 `Object.defineProperty` 换掉 `window.Notification`，经 `local_notifications` 发到原生。

- **无痕模式**：不持久化 cookie/存储，对登录态敏感的站有用。做成 preset 里的开关。

- **强制深色模式**：注入一个反色 CSS，一个脚本的事。

- **清除缓存并重启**：debug drawer 加一个按钮，排查站点问题时不用重装。

- **页面缩放**：`setTextZoom` 走原生而非 CSS hack，做成设置项。

- **preset 携带更多默认值**
  现在 preset 只有 `{name, url, bundleId}`。可扩展成每个预设自带默认脚本集合、默认 UA、无痕开关。

- **CLI `--json` 输出**：`pakem` 现在的输出偏人读，机器读需要结构化。

## 不做

- 系统托盘、关窗隐藏、全局快捷键、多窗口/多实例、多架构 —— 桌面概念，移动端不成立。
- 代理 —— 域名封锁换域名就解决，走代理方向不合规也不划算。
- 忽略证书错误 —— 安全风险。
- 拖拽上传 —— 移动端几乎没有拖拽场景。
