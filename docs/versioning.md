# 版本号策略

这个仓库里有四个地方写着版本号，之前它们都是随手定的：三个 preset 全是
`1.0.0` 从没动过，`pake_cli` 停在 `0.1.0`，`pake_shell` 那行是 `flutter create`
留下的默认值。本文定死每个号归谁管、什么时候动哪一位。

## 一条判据

semver 描述的是**这个交付物对它的消费者而言变了什么**。谁是消费者，决定了
版本号该跟着什么走——这一条能解掉本仓库全部四处的归属问题。

## 四个位点，现在只有一个真号

其余三个都是占位——不是忘了维护，是维护它们没有意义。

| 位点 | 消费者 | 状态 |
|---|---|---|
| `pake.json` / `presets/*.json` 的 `version` | 终端用户 | **真** —— 装在手机上那个 app |
| `packages/pake_cli/pubspec.yaml` | 开发者 | 占位——**暂无分发渠道**，见下节 |
| `packages/pake_shell/pubspec.yaml` | 无 | 占位，构建时被 `--build-name/--build-number` 覆盖 |
| `packages/pake_config/pubspec.yaml` | 无 | `publish_to: none` 的内部库，不维护 |

**壳不单独编号。** 它不是发布物，是被 `materialize` 铺进 workspace 的模板；
它的每一次变化都直接落在某个 app 的 version 上。想知道「4KVM 0.2.0 里跑的是
哪个壳」，去看 `fourkvm-v0.2.0` 这个 tag 指向的 commit——git 已经记着了，
再维护一个对用户不可见的号只是多一处要同步的地方。

## App 版本怎么 bump

一个 app 的内容 = 壳代码 + 那份 `pake.json`。**变化来自哪边不影响定位**，
只看用户感知：

- **major** —— 用户得重新适应或重新登录：换了目标站（不是换域名，是换站）、
  本地数据格式不兼容（比如锁的存储变了、装上得重设图案）
- **minor** —— 多了能用的东西：壳加了新功能（回主页键、页内查找、应用锁）、
  配置开了新权限或新注入脚本
- **patch** —— 用户什么都不用做就更好了：修 bug、换域名、换图标、性能

按这把尺子回看：三个 preset 从 `1.0.0` 那次构建之后加了应用锁、加了更新检测、
换过域名，早该 bump 过好几轮了。

## pake_cli 的号：现在别编

`pakem` 只能这么装（`README.md`）：

```bash
dart pub global activate --source path packages/pake_cli
```

**从本地路径装，没有分发渠道。** 没人能选择装 0.2.0 还是 0.3.0——clone 下来
装的就是 HEAD，描述环境时说的是 commit 不是版本号。按「有没有人依据它做决定」
这把尺子量，答案是没有，所以现在给它编号是空仪式。停在 `0.1.0` 不动。

**什么时候启用：** 出现分发渠道那天——发 pub.dev、release 里挂可执行文件、
走 brew，随便哪一个。判据很硬：**当有人能装到跟 HEAD 不同的版本时**，号才
开始承载信息。

**启用后的规则：** 0.x 期 **minor = breaking**（命令名、参数名、`pake.json`
schema、`ExitCodes` 分级、`--json` 输出结构），patch 是新功能和修 bug。
上 1.0.0 的判据同样要可检验，不能靠感觉：**roadmap「近期」里会动 schema 的
条目清空时**。现在还挂着两条（preset 携带更多默认值要改 schema、CLI `--json`
输出），离 1.0.0 还远——这本身就是
现在不该编号的旁证。

### 两处 bump 版本号救不了的 breaking

`tagFor()`（`pake_cli/lib/src/commands/release.dart`）拼 tag 的
`<bundleId 末段>-v<semver>` 规则，和 `versionCodeFor()` 的推导公式——改这两处，
受害的不是运行 CLI 的开发者，是**手机上已经装了包的终端用户**，而且不报错：

- 改 tag 规则 → 老包按老规则找 tag，新 CLI 发新规则的 tag，永远对不上，
  更新检测静默死亡
- 改 versionCode 公式 → 新包的数可能低于旧包，装机时才蹦
  `INSTALL_FAILED_VERSION_DOWNGRADE`

版本号是说给「即将运行 CLI 的人」听的，对「手机里已经装了包的人」一个字都
说不上。这两处**要么永不改，要么改的时候新旧规则同时认**，撑过一个所有用户
都升过一轮的兼容期。这条比编号规则重要得多。

## versionCode 是推出来的，但不止推导那一步

`version` 是唯一要手写的字段，`versionCode` 由 `versionCodeFor()` 从它推：
`1.2.3` → `10203`（`pake_config/lib/src/config.dart`）。

**但那不是装到手机上的最终值。** `pakem build` 走 `--split-per-abi`，Flutter
会再给每个 ABI 加一个偏移：

| ABI | 偏移 | `1.0.0` 实际 versionCode |
|---|---|---|
| armeabi-v7a | +1000 | 11000 |
| arm64-v8a | +2000 | **12000** |
| x86_64 | +4000 | 14000 |

所以 `aapt dump badging` 读出来的数比推导值大，这是对的，不是推导坏了。
一台设备只装得下其中一个 ABI 的包，同 ABI 内单调性成立（升级链路正确）；
**跨 ABI 的 versionCode 不可比**，别拿 arm64 的数去跟 v7a 的比。

同一个 version 要重发一次包时，在 json 里显式写 `buildNumber` 钉死推导结果
——那是后门，常态是不写。

### 降级装不上

Android 拒绝 versionCode 更低的包覆盖安装（`INSTALL_FAILED_VERSION_DOWNGRADE`）。
调 version 之前先确认新值推出来的 versionCode 高于**用户手上那个包**的，
不是高于仓库里最后一次构建的。

## 两条发布通道，同一套 tag 规则

- **`build-presets.yml`（CI）** —— 预设 app 走这条。密钥只在 GitHub secrets
  里，本机不放。
- **`pakem release`（本地）** —— 自己一次性打的 app 走这条。

两条都用 `pakem release` 拼 tag：`<bundleId 末段>-v<semver>`（`com.pake.fourkvm`
+ `0.2.0` → `fourkvm-v0.2.0`），壳里按同样规则筛。**手动建 release 时 tag 写错
就是静默失效**，这正是两条通道都过 CLI 而不是各写各的理由。

区别只在谁签、谁发，不在 tag。CI 那条一律先发成 **pre-release**——`pickUpdate()`
跳过 prerelease，所以包躺在 Releases 上但没有任何已装 app 会看见它；下载装到
真机验过，再在 GitHub 上取消勾选，那一刻才真正推给用户。

## 当前起点

三个 preset 重置到 `0.1.0`：`1.0.0` 是随手写的，而这几个 app 的更新链路
到现在一次都没真正走通过，`0.x` 更诚实。

重置安全，因为线上实际装机的只有 `presets-20260801-153907` 那批
（arm64 versionCode **2001** —— 当时 `buildNumber` 还默认写死 1），
而 `0.1.0` 推出来是 2100，高于它，能直接覆盖安装。8/23 那几次 CI 构建
（12000）没有分发给任何人。

往后：`0.2.0` → 2200，`1.0.0` → 12000，一路递增。

`pakem init` 给新 app 写的默认值仍是 `1.0.0`，不跟着改——那是别人拿这个 CLI
打自己的包时的起点，「装上就能用的第一版」叫 1.0.0 天经地义。重置到 `0.x`
是本仓库对自己那三个 preset 的判断，不是对所有人的建议。

## 不做：远程配置热更

注入脚本、UA 这些从远端拉、不重装 APK 就生效——技术上成立，
但它会引入第二个版本号轴（配置版本），而这个壳的配置改动频率根本撑不起
那套机制。真需要时再说，见 [`roadmap.md`](./roadmap.md)。

## 参照：tw93/Pake 为什么能共用一个号

桌面版兄弟项目 [tw93/Pake](https://github.com/tw93/Pake) 走的是完全相反的路
——**全仓库一个号**，`3.15.7` 同步写在 `package.json`（npm 的 `pake-cli`）、
`Cargo.toml`（Rust 壳）、`tauri.conf.json`（app 模板）三处。16 个预打包 app
挂在同一条 release 下，asset 名里连版本号都不带（`ChatGPT.dmg`、`DeepSeek.dmg`），
每次发版全量重打，没有单个 app 独立发版这回事。

**它能这么做，是因为 Pake 没有更新检测**（`Cargo.toml` 里 8 个 tauri 插件没有
`updater`）。那边的 app 版本号没有任何程序在读，只是个写在「关于」里给人瞄
一眼的构建标记——所以 DeepSeek 那版什么都没改也跟着升，没有任何后果。

这边不行：`pickUpdate()` 拿 app 的 `version` 跟 release tag 比，**比出来的结果
直接决定要不要给用户弹更新提示**。号不准就是弹错版本或者根本不弹。

两边的真号恰好调了个个儿：

| | tw93/Pake | pake_mobile |
|---|---|---|
| CLI 分发 | npm `pake-cli` —— 有渠道 | 本地路径 activate —— 无渠道 |
| **CLI 版本号** | **真，必须维护** | **空，暂不编号** |
| 更新检测 | 无 | 有 |
| **app 版本号** | **空，构建标记而已** | **真，代码读它做决策** |

判据自始至终是同一条：*有没有人（或程序）依据这个号做决定*。Pake 那边没人读
app 号，所以共用省事；这边是代码在自动读，所以必须独立且准确。

顺带一提，两边的灰度形状一致：Pake 用 `continuous`（prerelease，滚动 tag）
和 `V3.x.x` 分开两条 release，这边是同一条 release 的两个状态——先 prerelease
供自己验，取消勾选即转正。
