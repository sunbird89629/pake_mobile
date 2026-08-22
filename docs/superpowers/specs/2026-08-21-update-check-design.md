# 新版本检测与更新设计

给打包出的 app 加一条自更新链路：冷启动去 GitHub Releases 查有没有新版，有
就弹一次 dialog，点「更新」跳系统浏览器下 APK。同时给 CLI 加 `pakem release`，
把「发一个能被检测到的版本」这件事固化成一条命令。

更新的是**打包出的 App 自身**，不是 CLI、也不是 workspace 模板。动机很直接：
产物走侧载分发，没有商店的自动更新通道，用户手上的 4kvm 装完就永远停在那个
版本。

## 决策记录

| 问题 | 结论 |
|---|---|
| 更新源 | GitHub Releases API，仓库**硬编码** `sunbird89629/pake_mobile` |
| release 布局 | 所有 app 共用主仓，靠 tag 前缀区分 |
| tag 约定 | `<bundleId 末段>-v<semver>`，如 `fourkvm-v1.2.0` |
| 拉取 | `GET /releases?per_page=100`，**只拉一页** |
| 过滤 | 跳过 draft 与 prerelease |
| 挑选 | 取剩下 semver **最高**的，不是列表第一个 |
| 版本比较 | 手写三段比较，不引 `pub_semver` |
| 本地版本 | 读 `buildTime.version`（`assets/pake.json`），**不引 `package_info_plus`** |
| asset | 优先 `arm64-v8a` 的 apk；剩不止一个时按 app 名再筛；仍不唯一回落 `html_url` |
| 时机 | 冷启动异步查 + 24h 节流 + 设置页手动按钮 |
| 提示形式 | 每个新版号弹一次 dialog，「稍后」写入 `dismissedVersion` |
| 更新动作 | `url_launcher` 跳系统浏览器（**唯一新依赖**） |
| iOS | 自动检查关，设置页手动入口保留 |
| 总开关 | `RuntimeKeys.updateCheckEnabled`，默认 **true** |
| 网络 | `dart:io` HttpClient，不引 `package:http` |
| 失败 | 自动路径**一律静默**；只有手动按钮回显错误 |
| 代码位置 | `pake_shell/lib/src/update/`，纯函数 + fetcher 注入 |
| 发布侧 | `pakem release`，走 `ProcessRunner` 调 `gh release create` |
| release 是否构建 | **不构建**，只发 `~/.pake/out/<name>/` 里已归档的产物 |
| debug 签名 | **不拦**（见「已知代价」） |

## 架构

```
pake_shell/lib/src/update/
  update_check.dart     纯函数：解析 JSON → 筛前缀 → 比版本 → 选 asset
  update_service.dart   HttpClient fetcher + 节流 + 开关，唯一有副作用的一层
  update_dialog.dart    提示 UI
```

`update_check.dart` 里没有一行 Flutter、没有一行网络。它的入口签名是：

```dart
typedef Fetcher = Future<String> Function(Uri);
```

真实实现是 HttpClient，测试传一个返回固定字符串的假函数。不用 mock 包、不起
本地 server——版本比较、tag 前缀解析、asset 挑选这三处恰好是最容易静默出错
又最好测的，绑在网络里就测不动了。

### 为什么纯逻辑不下沉到 `pake_config`

`pake_config` 是纯 Dart，`dart test` 更快，看着更该放那儿。但 CLI 也依赖它，
而 CLI 永远用不上这堆代码。更新是 shell 独有的概念，塞进被 CLI 依赖的包里
只会把包的职责搞歪。

### 挂载点

冷启动的检查发在 `_PakeAppState`，但**弹窗必须等 `_locked` 变 false**。

`LockGate` 挂在 `MaterialApp.builder` 上、盖在 navigator 之上（见
`2026-08-01-pin-lock-design.md`）。这意味着此时 push 出来的 dialog 会被锁屏
**盖住**——它确实弹了，用户却看不见，等解锁时那次提示已经消费掉了
（`dismissedVersion` 甚至可能已写入）。所以订阅 `_locked`，解锁后再弹。

开了应用锁的用户是这条路径上唯一的受害者，而这个 bug 不会在任何 widget test
里暴露——测试里没人开锁。

## 几条需要留意的

### 「查不到更新」是常态，不是异常

`api.github.com` 在墙内经常不可达，而 4kvm 这类预设的用户恰恰在墙内。所以
自动路径上的任何失败——超时、DNS 污染、404、JSON 变形、限流——都必须静默
吞掉，一个 toast 都不能弹。会说话的只有设置页里那个手动按钮，那是用户主动
发起的，此时报错才有意义。

推论：**这个功能对墙内用户实际近乎失效**。它真正服务的是能连上 GitHub 的
那部分用户，以及你自己。接受这一点，不要为它加代理或镜像回落——那是另一个
量级的工程。

### 100 条 release 的天花板

所有 app 共用主仓，`/releases` 默认按创建时间倒序、一页 30 条。三个 app 交替
发版，某个 app 的最新 release 迟早会掉出第一页，那时它的用户**永远收不到
更新且毫无征兆**。

`per_page=100` 把这个天花板抬到 100 条 release，以当前发版频率能撑很多年。
但它是天花板，不是解决方案——真到那天要加分页。这一句必须留在代码注释里，
否则三年后没人想得起来。

不选「循环分页直到找到匹配」是因为：没匹配时它会把整个 release 历史拉完，
而「没匹配」恰好是别人 fork 之后的常态。

### 取最高版本，不是列表第一个

`/releases` 按创建时间排序。给旧版本补发一个 release（改个 asset、补个说明）
会让它排到最前面，此时取第一个就会把所有用户「升级」到更旧的包。逐个比 semver
才是对的。

同理，解析不出 semver 的 tag 一律当「没新版」丢掉，不要猜。

### `--split-per-abi` 让「取第一个 apk」变成错的

`pakem build` 用的是 `flutter build apk --split-per-abi`，一次出三个包：
`app-arm64-v8a-release.apk` / `app-armeabi-v7a-release.apk` /
`app-x86_64-release.apk`。原本设计的「按扩展名筛 `.apk` 取第一个」在这里会
按上传顺序随机发一个出去——**x86_64 装到任何一台真手机上都是失败的**，而
用户看到的只是系统安装器那句「应用未安装」。

所以先认文件名里的 `arm64-v8a`，认不出 ABI（单个通用包）才取第一个 apk。

残余代价：只剩 32 位的老设备会拿到一个装不上的 arm64 包。不为它引
`device_info_plus` 去读真实 ABI——那是给一类基本不存在的设备加一个依赖。

### prerelease 是灰度发布的闸门

过滤 draft 其实是防御性的——未登录的请求根本看不到 draft。有意义的是
prerelease：发一个勾了 prerelease 的 release，自己先装上验，验完取消勾选，
所有用户才会收到。这条通道是免费的，别关掉。

### 本地版本号哪来的

`assets/pake.json` 本来就打进包，`buildTime.version` 运行时直接可读，而
`build_pipeline.dart` 里 `--build-name=${config.version}`、
`patch/android.dart` 里 `versionName = "${config.version}"` 用的是同一个值。
所以它和 APK 里真实的 versionName 天然一致，不需要 `package_info_plus`。

代价是：如果有人手改了 `~/.pake/workspace` 里的 `pubspec.yaml` 版本号绕过
CLI，这个前提就断了。不为它做防御。

## 运行期配置

新增三个键，都带 `pake.` 前缀：

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `pake.updateCheckEnabled` | bool | `true` | 总开关，设置页可关 |
| `pake.lastUpdateCheckAt` | int | 无 | 毫秒时间戳，24h 节流用 |
| `pake.dismissedUpdateVersion` | String | 无 | 用户点过「稍后」的版本号 |

节流只约束自动检查。设置页那个按钮无条件发请求——它是唯一能拿到「已是最新版」
这个确定答复的路径，被节流掉就没意义了。

`dismissedUpdateVersion` 存版本号而不是布尔：点了「稍后」只对这一个版本生效，
下一版照弹。

## 设置页

`DebugDrawer` 里加一组：

- 当前版本（只读，`buildTime.version`）
- 「检查更新」按钮 → 转圈 → SnackBar 回显「已是最新版 x.y.z」/ 新版信息 / 错误
- 「启动时自动检查」开关（iOS 上这个开关控制的是……什么都不控制，见下）

### iOS 为什么只留手动

侧载的 IPA 点了链接也装不上——要 AltStore、重签名或 Xcode 重装。自动弹一个
「有新版」只是在告诉用户一件他无能为力的事。

但设置页里仍能手动查、看到版本号、跳 release 页：想升级的人找得到路，不想的
人不被骚扰。iOS 上「启动时自动检查」开关**不显示**。

## 发布侧：`pakem release`

```bash
pakem release                      # 读当前目录 pake.json
pakem release --notes "修了 X"      # 缺省走 gh --generate-notes
```

流程：读 `pake.json` 拿 `bundleId` + `version` → 拼 tag → 从
`~/.pake/out/<name>/` 找 `.apk`（有 `.ipa` 一并上传）→ `ProcessRunner` 调：

```
gh release create <tag> <assets…> --title <name> v<version> --generate-notes
```

用 gh 而不是直接调 REST：鉴权完全交给 gh，代码里不碰 token；`ProcessRunner`
现成，测试用 Fake 就能验参数拼得对不对。代价是多一个外部二进制依赖，
`doctor` 里加一行 `gh --version` 兜住。

**不构建**。你应该先把那个 APK 装到真机上验过再发——「build 完立刻上传」会
鼓励发一个没人装过的包，而这个包一发出去就会被所有用户拉下来。找不到归档
产物就退 3，提示先跑 `pakem build`。

tag 已存在时 gh 自己会报错，原样透出，不自己判重。

## 跟现有 CI 发布流程的关系

`.github/workflows/build-presets.yml` 现在发的 release 是
`presets-20260801-153907` 这种时间戳 tag，一个 release 里塞三个 app × 三个
ABI 的 APK。这类 release **不会被任何 app 检测到**——tag 前缀对不上，这正是
前缀过滤该有的行为。

也就是说：CI 那条流水线继续做它的持续构建，`pakem release` 是另一条独立的、
**面向用户的**发布通道。两者不冲突，但要清楚只有后者能推更新。要让 CI 也能
推更新，得让它按 app 分别发 tag——本期不做。

## 已知代价

1. **debug key 签的包不拦。** 明确决定。`build` 输出里有 `androidSigning`
   字段，但它没落盘到归档目录，`release` 拿不到；要拦就得先改归档结构。
   代价是：一旦发出去，用户覆盖安装只会看到系统安装器那句毫无信息量的
   「应用未安装」，排查成本很高。这个坑大概率会踩至少一次。
2. **100 条 release 天花板**，见上。
3. **墙内近乎失效**，见上。
4. 硬编码主仓意味着任何人用 `pakem` 打的任何包都会去查这个仓，拿到空匹配后
   静默——多一次无意义请求。用设置页开关关掉是唯一的止损。

### 2026-08-22 补：asset 按 app 名再筛一道

原来只按 ABI 挑 asset。一条 release 里挂了多个 app 的包时（CI 的 `presets-*`
正是这个形状），DADATU 的用户会拿到 `4KVM-app-arm64-v8a-release.apk`——
applicationId 不同，那不是升级，是**静默装上另一个 app**。

今天打不到，因为 `pakem release` 一次只传一个 app 的产物、而 CI 的 `presets-*`
tag 永远匹配不上前缀；**两个条件缺一个就中招**，而这两个都不是代码保证的。
现在多筛一道 app 名，筛完仍不唯一就回落 release 页面——发错包比让人多点一下
贵得多。

## 测试

`update_check_test.dart`（纯函数，无网络）：

- 版本比较：`1.2.0` vs `1.10.0`、`1.2` vs `1.2.0`、非法串
- 前缀筛选：`fourkvm-v1.2.0` 命中，`youtube-v9.9.9` 不命中
- draft / prerelease 被跳过
- 取最高版本而非列表首个（补发旧版的场景）
- asset 挑选：ABI 三件套里取 `arm64-v8a`；无 ABI 名取任一 apk；无 apk 回落
  `html_url`；一条 release 挂多个 app 时按 app 名筛出自己那个，筛不出唯一
  一个也回落 `html_url`
- 本地版本更高（开发版）时返回 null
- JSON 结构异常时返回 null 而不是抛

`update_service_test.dart`：节流窗口内不发第二次请求；开关关闭时一次都不发；
fetcher 抛异常时静默返回 null，**且不记时间戳**（记了就等于断网一次吞掉一整天）。

`pending_update_test.dart`：锁着时攥住不弹，解锁后弹且只弹一次。这条是唯一
能覆盖「弹窗被锁屏吃掉」那个 bug 的测试。

`debug_drawer_test.dart` 新增一组：手动检查的三种回显（已是最新 / 有新版 +
Download / 失败）。

`release_command_test.dart`（Fake `ProcessRunner`）：tag 拼接正确；缺产物退 3；
`--notes` 与 `--generate-notes` 互斥。

## 真机验证点

测试全绿不等于真机可用：

1. 冷启动弹窗真的出现，点「更新」真的跳到浏览器并下到 APK
2. **开着应用锁**冷启动：解锁之后才看到弹窗，不是解锁后什么都没有
3. 覆盖安装成功——即验证 release 签名链路是通的
4. 断网 / 飞行模式冷启动：无任何提示、无卡顿
5. 点「稍后」后重启 app 不再弹；`pakem release` 发一个更高版本后重新弹

## 不做

- 后台静默下载、增量更新、强制更新
- 墙内镜像 / 代理回落
- iOS 的 `itms-services` 安装（要 HTTPS 托管 plist + 企业签名）
- 更新渠道（stable/beta 双轨）——当下只有一个发布者，开关不会被拨
