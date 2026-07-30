---
title: "pake_mobile — 网页转移动端 App 构建工具设计"
date: 2026-07-30
status: approved
---

# pake_mobile

把任意网页打包成 Android / iOS App 的构建工具。单一 Flutter 代码库出双端，CLI 为唯一入口。

## 动机

现有方案 [PakePlus](https://github.com/Sjj1024/PakePlus) 把移动端拆成两个独立仓库：`PakePlus-Android`（原生 Kotlin）和 `PakePlus-iOS`（Swift）。同一个功能要实现两遍，改一处漏一处。

`pake_mobile` 的**唯一核心目标是消除这个双代码库成本**：一套 Dart 代码同时产出 Android 和 iOS。

次级目标（由核心目标顺带解决）：把 PakePlus 编译期写死的功能开关变成**运行时可调**。

## 范围

### 做

- 单一代码库构建 Android APK + iOS IPA
- 全屏 WebView 承载目标网页
- 少量原生设置壳：切 URL、切 UA、注入脚本开关、清缓存、看日志、看请求
- 运行时可调配置（改 UA 不需要重新构建）
- CLI 为唯一构建入口；GitHub Actions 只是在 CI 里调同一个 CLI

### 不做（YAGNI）

- **多站点容器** —— 不做 tab / 侧边栏 / 站点管理
- **App Store 上架** —— iOS 走自签 / 侧载，因此不需要绕 App Store Review Guideline 4.2（Minimum Functionality），壳里不必为过审塞功能
- **桌面端与 Web 平台** —— 桌面端已有 Pake；且 `flutter_inappwebview` 不支持 Linux
- **注入脚本市场 / recipe 生态**

## 技术选型

Flutter + [`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview)。

### 为什么是 Flutter

需求包含「运行时可调的原生设置壳」，因此需要一个真正的跨平台 UI 层——这是 Flutter 相对 Tauri 2 mobile / Capacitor 的决定性优势。若只要纯全屏 WebView，Flutter 引擎的体积开销无法证成，届时原生模板或 Tauri 更合适。

已有可直接复用的自有包：

| 需求 | 包 | 说明 |
|---|---|---|
| 设置页输入 / 选择 | `debug_sheet` | `DebugInputSheet` 自带输入历史；`DebugSelectSheet` 返回选中索引。README 的设计场景原文即「paste a staging URL, switch WebView engines, flip a feature flag」 |
| 运行时配置持久化 | `get_storage` | 同步 KV，读配置无需 await。`debug_sheet` 内部已依赖它 |
| 日志 | `logger_utils` | 纯 Dart，CLI 与 App 壳共用；带 daily-rotated file sink |
| 构建编排 / 版本号 | `flutter_ci_tools` | CLI 侧复用 |

**`http_inspector` 不适用**：它是 Dio interceptor，而 WebView 请求走原生网络栈，不经过 Dio。网络检查另行设计（见「网络检查」）。

### 已知风险

`flutter_inappwebview` 的 stable 版本停在 6.1.5（2024-10-08），`6.2.0-beta.3` 发布于 2026-02-04，仓库最后活动 2026-02，221 个 open issue。

**缓解**：fork 后以 git dependency 引用，遇坑自行修复。本地 `~/ai/in_app_webview/flutter_inappwebview` 已有 upstream clone（当前 `master`，已合入 `6.2.0-beta.3`），需先 fork 到自己账号。修复 WebView 层问题的能力已在 PakePlus-Android 的 WASM streaming shim 上验证过。

### 体积预期

APK（`--split-per-abi`）约 10–12 MB，IPA 约 15 MB。高于 PakePlus 宣称的 < 5 MB。自用场景下可接受，不作为优化目标。

## 架构

### 仓库结构

```
pake_mobile/
├── packages/
│   ├── pake_config/     共享配置模型：CLI 写，壳读
│   ├── pake_shell/      Flutter 模板壳
│   └── pake_cli/        Dart CLI（打包器）
└── .github/workflows/build.yml    仅调用 pake_cli
```

CLI 用 Dart 而非 Node，理由是 `pake_config`：配置模型只有一份代码，CLI 序列化、壳反序列化，schema 不可能漂移。Node 实现需维护两份 schema 并依赖人工保持一致。

### 配置分两层

PakePlus 只有一层（编译期 `app.json` 中约 20 个布尔开关），改 UA 需重新构建。本设计分两层：

| | 构建期 `pake.json` | 运行期 `get_storage` |
|---|---|---|
| 内容 | app 名、bundle id、图标、版本号、初始 URL、**系统权限声明** | 当前 URL、UA、注入脚本开关、全屏、手势、缓存策略、日志级别 |
| 谁写 | CLI | 设置页 |
| 为何在此层 | 需落进 `AndroidManifest.xml` / `Info.plist` / gradle，物理上无法运行时修改 | 纯 Dart / WebView 行为，运行时完全可改 |

**启动逻辑**：runtime 层为空时，用 build-time 层默认值初始化。设置页只写 runtime 层。「重置」= 清空 runtime 层，回落到构建时默认。

系统权限（相机 / 麦克风 / 定位）必须留在构建期——这是平台约束，不是设计选择。

## App 壳

### 组件结构

```
main()
 ├─ initLogging()          logger_utils，带 daily-rotated file sink
 ├─ GetStorage.init()      runtime 配置层
 └─ PakeApp
     └─ Stack
         ├─ WebViewPage    全屏 InAppWebView，主界面
         ├─ EscapeHatch    角落隐形手势区
         └─ [DebugDrawer]  设置壳，按需 push
```

### DebugDrawer 各项实现

| 设置项 | 实现 |
|---|---|
| 切 URL | `DebugInputSheet`，自带历史 |
| 切 UA | `DebugSelectSheet` + 预设列表（iOS Safari / Android Chrome / Desktop / 自定义） |
| 注入脚本开关 | 列表 + Switch，写 `get_storage` |
| 清缓存 / Cookie | `CookieManager` + `WebStorageManager` + `clearAllCache` |
| 看日志 | 读回 `logger_utils` 的 rotated file sink |
| 看请求 | 自建面板，见「网络检查」 |

### EscapeHatch

`InAppWebView` 吞掉所有触摸事件，因此设置壳入口必须位于 Flutter 层，不能依赖网页内按钮。更关键的是：**网页加载失败白屏时，用户仍须能进入设置页改回 URL**，否则 app 变成砖。

实现：`Stack` 顶层放左上角 44×44 透明 `GestureDetector`，长按 1.5 秒打开 `DebugDrawer`。不占视觉、不易误触、完全独立于 WebView 状态。

### 注入机制

构建期把 `scripts/*.js` 与 `*.css` 打进 assets，运行期每个脚本一个开关。

```dart
UserScript(source: ..., injectionTime: atDocumentStart)   // hook 类脚本
UserScript(source: ..., injectionTime: atDocumentEnd)     // 改 DOM / 去广告
```

**约束**：`addUserScript` / `removeUserScript` 只在下一次页面加载生效（`WKUserContentController` 的语义）。因此设置页拨动开关的实际行为是「改配置 → 自动 reload」。UI 必须明示这一点。

CLI 在物化脚本时自动为每个脚本包裹 try/catch，单个脚本抛异常不得导致整页失效。

### 网络检查

`http_inspector` 不可用（见「技术选型」）。改用两个手段互补：

| 手段 | 覆盖范围 | 能拿到 body |
|---|---|---|
| 注入 JS hook 包装 `fetch` + `XMLHttpRequest`，经 `callHandler` 回传 Dart | 页面内 JS 发起的请求 | 是 |
| `onLoadResource` 回调 | document / 图片 / CSS / 字体等资源加载 | 否，仅 URL + 时序 |

Dart 侧收进环形缓冲（保留最近 200 条），设置页展示列表 + 详情 + cURL 导出。

这条路子是 PakePlus 中 `vConsole.js` 的思路，但把数据取到了 Dart 侧，因此可持久化、可导出、可与 app 日志合并查看。

**待验证**：`http_inspector` 的 UI 层能否复用。其模型基于 Dio 的 `RequestOptions` / `Response`，很可能耦合。若耦合则自行实现简单列表，沿用其「列表 + 详情 + cURL 导出」的信息布局。

## CLI

### 命令面

```bash
pakem init                       # 生成 pake.json 模板
pakem build <url> --name X       # 主命令
pakem icon <path|url>            # 抓站点图标 / 转格式
pakem doctor                     # 环境与签名检查
```

可执行名为 `pakem`（`pake_mobile` 过长）。

`build` 的 flag：`--platform android,ios`、`--config`、`--icon`、`--bundle-id`、`--version`、`--inject <file>`（可重复）、`--team-id`、`--profile`、`--json`。

`--json` 输出单个 JSON 对象，对齐 Pake 的 agent 契约。

**`--platform` 默认值**：`android`。即便在 macOS 上也不默认双端——iOS 构建需要签名参数，静默尝试后失败会让首次使用者困惑。要 iOS 就显式写 `--platform ios` 或 `--platform android,ios`。

**配置查找顺序**：`--config <path>` 显式指定 > 当前目录 `pake.json` > 无配置文件（全部由 CLI flag 提供，缺必填项则报配置错误）。三者不叠加，取第一个命中的来源；CLI flag 始终覆盖文件中的同名字段。

### 构建流水线

```
pake.json + CLI flags → PakeConfig（pake_config 校验）
  → 同步到固定 workspace
  → 物化配置：assets/pake.json · scripts/ · 图标 · gradle appId+名字 · Info.plist · 权限
  → flutter build apk --split-per-abi  /  flutter build ipa --export-options-plist
  → 产物归档 + 输出路径
```

### 固定 workspace

**问题**：Flutter 增量缓存位于项目目录内（`.dart_tool/`、`build/`、`android/.gradle/`、`ios/Pods/`）。若每次 build 复制模板到新临时目录，缓存全丢，每次均为冷构建（Android 数分钟，iOS 更久），「一条命令快速出包」不成立。

**解法**：单一 workspace 实例 + 幂等同步。

```
~/.pake/
├── workspace/       唯一的 Flutter 项目实例，缓存长期驻留
└── out/<app>/       产物归档
```

每次 build 只覆写会变的文件，其余不动：

- 仅改 URL（最常见）→ `applicationId` 不变 → 增量构建，快
- 换 app 名 / bundle id → Gradle 部分任务失效，但 Kotlin 编译产物仍可复用 → 显著快于冷构建

**并发**：单 workspace 不支持并行构建两个 app。用 `~/.pake/workspace/.lock`；第二个进程**直接报错退出，不排队**——排队会让 `--json` 的 agent 调用静默超时，报错更诚实。

### iOS 签名

`--team-id` + `--profile` → 生成 `ExportOptions.plist` → `flutter build ipa --export-options-plist`。

自签场景最常见的两个失败是 **profile 过期**与 **bundle id 不匹配**。两者在 build 前检查：

- `security find-identity -v -p codesigning` 确认有可用证书
- 扫 `~/Library/MobileDevice/Provisioning Profiles/` 确认 profile 存在且未过期

失败即明确报错，不等 `xcodebuild` 输出。

### CI

Actions workflow 只做三件事：装 Flutter → `dart pub global activate --source path packages/pake_cli` → `pakem build $URL --name $NAME --json`。逻辑零分叉。

CI runner 每次为新环境，必然冷构建。可用 Actions cache 缓存 pub cache 与 gradle cache 缓解，但云构建始终慢于本地——这是物理限制，非设计缺陷。

## 错误处理

### CLI

**校验前置**：`pake_config` 在 CLI 阶段查完 URL 合法性、bundle id 格式、图标文件存在、注入脚本可读。配置错误须在亚秒级报出，不得由 Gradle 充当校验器。

**构建失败输出**：gradle / xcodebuild 全量输出写入 `~/.pake/logs/`（`logger_utils` 的 file sink），终端只显示提取的关键行与日志路径。

**退出码分级**：

```
1 = 配置错误    2 = 环境缺失    3 = 构建失败
```

`--json` 模式下错误同样为 JSON（`{"ok": false, "error": {...}}`），配合退出码使 agent 可编程处置。

### 运行时

- `onReceivedError` / `onReceivedHttpError` → 重试页 + 显式「打开设置」按钮。EscapeHatch 是兜底通道，但有明确错误页时应给明确按钮——白屏被困是这类 app 最常见的失效方式
- 区分「无网络」与「URL 错误」，提示不同：前者让用户等待，后者引导用户改配置
- 注入脚本自动包 try/catch，错误经 `onConsoleMessage` 收进日志
- `get_storage` 读到损坏配置 → 回落 build-time 默认，不崩溃

## 测试

| 层 | 方法 | 理由 |
|---|---|---|
| `pake_config` | 纯 Dart 单测：合并优先级（flags > pake.json > defaults）、校验规则、序列化往返 | 逻辑最密集，投产比最高 |
| `pake_cli` | 给定 config → golden file 比对生成的 `AndroidManifest` / `Info.plist` / gradle 片段。**不跑真实构建** | 秒级反馈，覆盖最易出错的字符串拼接 |
| `pake_shell` | widget test：改 UA → 断言 `get_storage` 写入；拨脚本开关 → 断言触发 reload | WebView 本身需真机，不测 |
| 集成 | smoke test 真实构建一次 debug APK，断言产物存在。**仅在 CI 跑** | 本地每次跑过慢 |

### 手动回归清单

需真机 + 真站点，自动化无法覆盖。以下四项来自 PakePlus-Android 的实际踩坑记录，每次发版执行：

- [ ] WASM streaming compile（已有 shim 修复经验）
- [ ] `blob:` / `data:` URL 下载
- [ ] 输入法遮挡（`windowSoftInputMode`）
- [ ] 4K 视频播放（Pixel 8 已验证基线）

## 未决事项

1. `http_inspector` 的 UI 层是否可从 Dio 模型解耦复用——需实际阅读其源码后决定。若不可，自行实现简单列表面板。
2. `flutter_inappwebview` fork 的目标 ref：跟 `master`（含 `6.2.0-beta.3`）还是钉在 `6.1.5` stable。倾向 `master`，因为需要较新的 Flutter 兼容性；首次集成时验证。
