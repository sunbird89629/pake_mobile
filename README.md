# pake_mobile

把任意网页打包成 Android / iOS App。一套 Dart 代码出双端。

## 在线构建（不用装任何东西）

现阶段，要在本地要跑 `pakem` 得先有 Flutter SDK + Android SDK + JDK，这不是随手就能凑齐的
一套。推荐走 GitHub Actions：

1. **[Fork 这个仓库](https://github.com/sunbird89629/pake_mobile/fork)**
   ——`workflow_dispatch` 要仓库的写权限，在别人的仓库里你看不到
   `Run workflow` 那个按钮。
2. 去你 fork 的 **Actions** 页 → 左边选 **build** → 右上 **Run workflow**
3. 填表：URL 和 app 名必填，bundle id 默认 `com.pake.app`（打多个 app 要各不
   相同，否则装在一起会互相覆盖）；图标留空会自己从站点抓，版本留空是 `1.0.0`
4. 跑完在仓库的 **Releases** 里取包——不用去 Artifacts，那个 90 天就过期了

**装哪个包**：一次出三个（`--split-per-abi`），现役手机基本都装
`app-arm64-v8a-release.apk`。

有 Gradle 缓存时约 4~5 分钟（实测）；fork 后第一次跑是冷缓存，要明显更久。

**这样打出来的包，app 里的「检查更新」不会有反应**，不是坏了：壳里的
`updateRepo` 写死指向本仓，而你的 release 发在自己的 fork 里，两边对不上。
自己构建的包靠自己重新构建来更新。

### fork 出来的包不能升级，除非配一次密钥

fork 里没有签名密钥，构建会回落到 Flutter 的 debug key，而**那个 key 每次
构建都不一样**。后果不是装不上，是装得上但升不了级：第二次构建出的包想覆盖
第一次那个，会被系统以签名不符拒绝，只能卸载重装、丢掉 app 里的所有数据。
构建结果页（job summary）会标出本次是哪种签名。

自用的话忍一次卸载重装也行。要能持续更新，就在你自己的 fork 里配一次密钥
（[生成方式](#android-发布签名)），把它设成三个 repo secret：

| secret | 值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 < keystore.p12 \| tr -d '\n'` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | key alias |

配好之后每次构建都用同一张证书签，包与包之间就能正常覆盖升级了。
**这个 keystore 丢了就没法再给同一个 app 发更新**，备份它。

## 配置分两层

| | 构建期 `pake.json` | 运行期（设置页） |
|---|---|---|
| 内容 | app 名、bundle id、图标、版本号、初始 URL、系统权限 | 当前 URL、UA、注入脚本开关、缓存策略、更新检查 |
| 谁写 | CLI | 设置页 |

改 UA 不需要重新构建。运行期层为空时回落构建期默认；「重置」= 清空运行期层。
不过运行期这一层**正式包里只露出一半**，见下。

## 设置页入口

底部悬浮工具栏上的 ⚙。它浮在网页之上，上滑隐藏、下滑显示，滑到页面顶部或
换页时必然出现（网页播放器进全屏时也让位）。同一条栏上还有后退和刷新。

**这条栏没有关闭开关**，这是刻意设计：它和错误页上的按钮是仅剩的两个设置
入口，允许关掉就等于允许用户把自己锁在外面。

系统返回键被接管成网页后退，退无可退时才退出 app——壳里只有一个页面，返回
键的默认行为（直接杀掉 app）在网页场景里几乎总是误操作。

### 正式包里的设置页更短

调试用的那几项（**URL、User agent、Capture network、View logs、View
requests、Reset to build defaults**）只在 debug 构建里显示。正式包留下的是
注入脚本开关、App Lock、版本与更新检查、清缓存——都是普通用户按得懂、也确实
用得上的。

藏 URL 和 UA 不只是嫌乱：这两项改错了壳就变成一个打不开的空白页，而唯一的
退路（Reset）恰好也在被藏起来的那一组里。

`pakem build` 出的包永远是 release，所以默认就是短的那一版。包已经装在真机
上、要现场看日志或抓包时，加一个开关重新出一版：

```bash
pakem build https://example.com --debug-ui
```

它仍然是 release 构建（签名、体积、性能都不变），只是把那几项放回设置页。

## 检查更新

打好的 app 冷启动时会去主仓的 GitHub Releases 查有没有新版，一天最多一次；
有就弹一次提示，点「更新」跳系统浏览器下 APK。设置页里能手动查、能关掉自动
检查。**iOS 不自动查**——侧载的 IPA 点了链接也装不上。

发布一个能被检测到的版本：

```bash
# 1. 改 pake.json 的 version，2. 构建，3. 装到真机上验过，4. 再发
pakem build https://www.4kvm.site
pakem release --notes "修了 X"
```

`version` 是唯一要改的字段：Android 的 `versionCode` 从它推导
（`1.2.3` → `10203`），不用再单独维护 `buildNumber`——系统只认 versionCode，
它不跟着走的话 bump 完版本号两个包在系统眼里一模一样。同一个版本要重发一次
包时，在 pake.json 里显式写 `buildNumber` 钉死它。

推导值不是装机的最终值：`--split-per-abi` 会再加一个 ABI 偏移（arm64 +2000，
所以 `1.0.0` 的 arm64 包实际是 12000）。什么时候动哪一位、四处版本号分别归谁
管，见 [`docs/versioning.md`](./docs/versioning.md)。

tag 由 CLI 拼成 `<bundleId 末段>-v<version>`（`com.pake.fourkvm` + `1.2.0`
→ `fourkvm-v1.2.0`），app 端按同样的规则筛——**手动建 release 时 tag 写错
就是静默失效**，这正是 `pakem release` 存在的理由。它需要 `gh` 并且已登录，
`pakem doctor` 会报它在不在。

`pakem release` **不构建**：它只发 `~/.pake/out/<app>/` 里已经躺着的那份，
逼你先把包装到真机上验过。想灰度就加 `--prerelease`（或事后在 GitHub 上勾）
——app 端跳过 prerelease，验完再取消勾选。取消后**最长要等一分钟才生效**：
未登录的 `api.github.com` 响应有约 60 秒 CDN 缓存。

四条已知边界，都是刻意接受的：

- **`pakem release` 不拦 debug key 签的包。** 发出去了用户覆盖安装只会看到
  「应用未安装」，排查成本很高。发布前自己确认 `pakem build` 输出里的
  `androidSigning`。（预设那条 CI 通道会拦，见下）
- **只拉一页 100 条 release。** 所有 app 共用主仓，某个 app 的最新版被挤出
  这 100 条就再也检测不到
- **墙内基本查不到。** `api.github.com` 不可达时一律静默——不弹错、不重试
- **只给 arm64 设备推包。** 构建是 `--split-per-abi` 的三个 APK，app 端认
  `arm64-v8a`；只剩 32 位的老设备拿到的包装不上。一条 release 里挂了多个 app
  的包时再按 app 名筛一道，筛不出唯一一个就回落到 release 页面让人自己挑

## 预设站点

`presets/` 下一个 json 一个 app，手动触发 `build-presets.yml` 会把它们并成
矩阵一次性全构建。加一个站点 = 加一个 json 文件。

**预设 app 只由 CI 签名和发布，release key 不放在笔记本上。** 这不是洁癖：
本地和 CI 各存一张证书的话，没有任何东西能保证它们是同一张，而一旦不是，
先从 Releases 页面下过包的用户再装另一条路径出的版本就是「应用未安装」，
他也不会知道为什么。收敛到一处，这个问题就不需要靠核对来维持。

每个 preset 各发一条自己的 release，tag 和 `pakem release` 同一个规则
（`fourkvm-v1.2.0`）——workflow 直接调 `pakem release`，不在 YAML 里重写一遍
tag 格式。发出来一律是 **pre-release**，所以已装的 app 不会看见它：

```
改 presets/4kvm.json 的 version → 跑 build-presets.yml
  → fourkvm-v1.2.0 (pre-release)
  → 下载 APK 装到真机上验
  → 在 GitHub 上取消 pre-release 勾选 → 用户收到更新提示
```

版本号没动过的 preset 会被跳过（job summary 里会写明是哪个、为什么）——一次
跑构建全部三个 app，「这个版本已经发过了」是常态，不是错误。

**签名不对就不发。** 没配 `ANDROID_KEYSTORE_*` secrets 时构建会回落 debug
key，那种包装不到任何别的构建之上；workflow 查到 `androidSigning` 不是
`release` 就直接失败，产物仍然留在 Actions artifacts 里供排查。

json 里的 `version` 会传给构建，漏写就回落 CLI 的默认值 `1.0.0`。它定的是
versionCode——不 bump 的话新出的包在系统眼里和上一个一模一样，装到同一台
手机上分不出新旧。（这批包不参与更新检查，见上一节。）

域名被墙时的处置是**换域名，不是加代理**：GFW 按域名封锁，同一站点的备用
域名往往直连可达——`4kvm.site`、`dadatuys.com` 都是这么换过来的。

## 应用锁

设置页里可以开一道手势图案锁（3×3 九宫格，至少连 4 个点）：冷启动时锁，
切后台超过 30 秒回来也锁。图案有方向，`1-2-3` 和 `3-2-1` 不是同一个。

存的是图案的 SHA-256，**不加盐**：威胁模型是「别人拿起我的手机」，不是取证
分析——拿到设备的人本来就能本地枚举全部合法图案（不到 40 万种，秒级）。
哈希换来的只是「翻一眼存储文件不会直接看到密码」这一件事。

**忘了图案没有恢复路径**——锁屏盖住了底部工具栏，只能清应用数据或重装。
这是刻意的：留后门的锁不叫锁。锁着的时候系统返回键也不响应。

## 退出码

`1` 配置错误 · `2` 环境缺失 · `3` 构建失败。`--json` 模式下错误同样是 JSON。

## Android 发布签名

不配密钥也能出包，但会用 Flutter 的 debug key 签——**那种 APK 换台机器
或换一次 CI 运行，签名指纹就变了**，装不到已有安装之上，也无法升级。
`pakem build` 的结果里 `androidSigning` 字段写明本次到底用了哪种。

预设 app 走 CI 那条通道，密钥只在 GitHub secrets 里，本机不需要配。下面这套
是给自己在本地打、用 `pakem release` 发的 app 用的。

配置方式是在 `~/.pake/signing.properties` 放四行（`storeFile` 用绝对路径）：

```properties
storeFile=/Users/you/.pake/pake-release.p12
storePassword=…
keyAlias=pake
keyPassword=…
```

没有密钥就先生成一个：

```bash
keytool -genkeypair -v -keystore ~/.pake/pake-release.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias pake \
  -dname "CN=pake, O=pake_mobile, C=CN"
chmod 600 ~/.pake/pake-release.p12 ~/.pake/signing.properties
```

这个文件放在 workspace 之外是必须的：`~/.pake/workspace` 每次构建都会被
模板覆写，放里面会被冲掉；放仓库里则等于把私钥提交上去。

**keystore 丢了就没法再给同一个 app 发更新**，用户只能卸载重装。备份它。

CI 用同一套约定，密钥来自三个 repo secret：`ANDROID_KEYSTORE_BASE64`
（`base64 < keystore.p12 | tr -d '\n'`）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`。没设这些 secret 时 build workflow 照常出包，但会在
job summary 里标出 debug 签名并给一条 warning。fork 出来用
[在线构建](#在线构建不用装任何东西)的场景同理，那边写了后果。

## 开发

```bash
cd packages/pake_config && dart test
cd packages/pake_cli && dart test          # smoke test 默认跳过
cd packages/pake_shell && flutter test
```

打了 `smoke` tag 的两个用例默认跳过，要显式跑：

```bash
# 两个一起跑：真实构建一次 APK + 图标发现（数分钟，冷 Gradle）
cd packages/pake_cli && dart test --tags smoke --run-skipped

# 只跑真打网络的图标发现验证（几秒）
cd packages/pake_cli && dart test test/icon_discovery_live_test.dart --run-skipped
```

`--tags smoke` 只选中用例，不解除 `dart_test.yaml` 里的 `skip:`；
必须带 `--run-skipped` 才会真正执行。

**CI 不跑这两个。** `build.yml` 里那个叫 `smoke` 的 job 跟测试标签没有关系
——它验的是构建出来的 APK 里 `pake.json` 对不对，一行 `dart test` 都不跑。
所以图标那个用例哪天因为 x.com 改版而变红，只会红在你手上，不会把 CI 搞红。

发版前跑 [手动回归清单](docs/manual-regression.md)。
