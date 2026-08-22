# 检查更新：首次验证计划

一次性的爬坡计划，验证 `pakem release` + 壳内检测这条链路真的通。
跑完之后，日常发版只需要 `docs/manual-regression.md` 里那六条勾选项。

设计文档：`docs/superpowers/specs/2026-08-21-update-check-design.md`

## 为什么不直接拿 4kvm 试

仓库是公开的，`pakem release` 发的是正式 release——发出去那一刻所有已装
4kvm 的人都会被推到那个包上。所以主体验证用一个**一次性测试 app**：
换个 bundleId 就换了 tag 前缀，跟任何真实用户的更新链路完全隔离，可以随便
发十个版本再删掉。最后才在 4kvm 上做一次真实的端到端。

---

## 阶段 0 · 桌面预检（不用手机）—— 已于 2026-08-22 跑完，全过

失败在这里发现，比装到手机上再发现便宜一个数量级。

- [x] **签名指纹对得上** —— 本地构建、CI 构建、keystore 里的那把，
      三者同一张证书 `CN=pake, O=pake_mobile, C=CN`：

      ```
      d280bfe0f946cc3de6e2675b8342d433090774598397cacaab05e488f80219e3
      ```

      **这条本来是最大的未知**：CI 用的是 `ANDROID_KEYSTORE_BASE64` secret，
      本地用 `~/.pake/pake-release.p12`，仓库里看不出是不是同一把。现在确认
      是同一把 —— 从 CI 预设包装机的用户，能被本地 `pakem release` 发的包
      覆盖安装。复现命令：

      ```bash
      APKSIGNER=~/Library/Android/sdk/build-tools/36.1.0/apksigner
      $APKSIGNER verify --print-certs ~/.pake/out/4kvm/app-arm64-v8a-release.apk | grep SHA-256
      gh release download presets-20260801-153907 -p '4KVM-app-arm64-v8a-release.apk'
      $APKSIGNER verify --print-certs 4KVM-app-arm64-v8a-release.apk | grep SHA-256
      ```

- [x] **真实 API 响应能被解析** —— HTTP 200，8 条 release，
      `tag_name` / `draft` / `prerelease` / `html_url` / `assets[].browser_download_url`
      全在。拿真实 body 喂 `pickUpdate`：三个预设都是「无新版」（现有 tag 一个
      都不匹配，符合预期）；把最新那条的 tag 改成 `fourkvm-v1.0.1` 后正确挑出
      `4KVM-app-arm64-v8a-release.apk` —— **CI 的 asset 名带 app 名前缀、本地
      构建的不带，两种命名都能被 `arm64-v8a` 匹配上**。标成 prerelease 后立刻
      消失，版本填 1.0.1 后也不再提示。

- [x] **tag 命名空间干净** —— 100 条内没有任何 `<前缀>-v<semver>` 形式的 tag。

- [x] **`gh` 就绪** —— 2.96.0，已登录 `sunbird89629`，scope 含 `repo`。

### 阶段 0 顺带挖出来的三件事

1. **已装的那批用户拿不到更新提示。** CI 那个 4KVM 包（2026-08-01 构建）
   里根本没有检查更新的代码。这功能是从**下一个构建**开始才生效的，
   老包只能靠人工通知升一次。别把「老手机上没弹」当 bug 查。

2. ~~**`buildNumber` 不会跟着 `version` 走。**~~ **已修**。原来它默认写死 1
   并直接决定 `versionCode`，只改 `version` 的话 `versionCode` 一动不动。
   现在 `versionCode` 从 `version` 推导（`1.2.3` → `10203`），`buildNumber`
   降级成「同版本重发一次包」时钉死它的后门。

   **对阶段 1 的影响**：新构建的 arm64 versionCode 是 `2000 + 10000 = 12000`，
   比已装的 CI 包（2001）大，覆盖安装方向没问题。1.0.0 → 1.0.1 也会真的从
   12000 涨到 12001，不再是同一个数。

3. ~~**多 app 混装的 release 会发错包。**~~ **已修**。挑 asset 原来只看文件名
   里有没有 `arm64-v8a`，不看 app 名；把 CI 那种一条 release 挂九个 APK 的
   tag 改成 `dadatu-v1.0.1`，dadatu 的用户拿到的是
   `4KVM-app-arm64-v8a-release.apk`——applicationId 不同，那不是升级，是静默
   装上另一个 app。现在按 ABI 筛完剩不止一个时，再按 app 名筛一道；仍不唯一
   就回落 release 页面让人自己挑。

## 阶段 1 · 造一个一次性测试 app

```bash
cat > /tmp/updatetest.json <<'JSON'
{
  "name": "UpdateTest",
  "url": "https://example.com",
  "bundleId": "com.pake.updatetest",
  "version": "1.0.0"
}
JSON
```

- [x] **构建 1.0.0 并存档**（下一次 build 会覆盖同名 APK，不存就没了）：

      ```bash
      pakem build --config /tmp/updatetest.json
      mkdir -p /tmp/updatetest-1.0.0 && cp ~/.pake/out/updatetest/*.apk /tmp/updatetest-1.0.0/
      ```

      确认输出里 `androidSigning` 是 `release`，不是 debug。

- [x] **装到真机**：`adb install -r /tmp/updatetest-1.0.0/app-arm64-v8a-release.apk`

- [x] **发 1.0.0**——这一步的目的不是给谁用，是拿一个
      「已是最新版」的确定答复，证明网络 + 解析 + tag 匹配三件事全对：

      ```bash
      pakem release --config /tmp/updatetest.json --notes "baseline"
      ```

      设置页点 **Check for updates** → 期望 `Already on the latest version (1.0.0)`。
      **看到这句才说明链路通了**；看到 `Check failed` 是网络，看到「有新版」是
      版本比较写反了。

- [x] **造 1.0.1**：改 `/tmp/updatetest.json` 里的 `version` 为 `1.0.1`
      （**不要用 `pakem build --version` 覆盖**——build 用命令行值、release 用
      json 值，分叉了就会 tag 写 1.0.1 而包里自称 1.0.0，装完还一直提示更新）：

      ```bash
      pakem build --config /tmp/updatetest.json
      pakem release --config /tmp/updatetest.json --notes "test update"
      gh release edit updatetest-v1.0.1 --prerelease   # 先扣上，验负向用例
      ```

## 阶段 2 · 负向用例（此时 1.0.1 还是 prerelease）

每次冷启动前都要**真的冷启动**，热切回来不触发：

```bash
adb shell am force-stop com.pake.updatetest
adb shell monkey -p com.pake.updatetest -c android.intent.category.LAUNCHER 1
```

24 小时节流的解法：设置页点一次 **重置**（它会清掉 `lastUpdateCheckAt`、
`dismissedUpdateVersion` 和开关），或者干脆卸载重装。

- [x] **prerelease 不推** —— 2026-08-22 验过：`updatetest-v1.0.1` 标着
      prerelease 时冷启动无提示，取消勾选后同样的冷启动弹出提示。
      **一定要成对做**，只看到「不弹」证明不了任何事——一次静默的网络失败
      长得一模一样。
- [x] **关掉开关不查** —— 2026-08-22 验过。注意操作顺序：**先 Reset 再关开关**，
      反过来的话 Reset 会把开关恢复成默认的「开」。
- [x] **飞行模式静默** —— 2026-08-22 验过：无提示、无报错页；恢复网络后
      立刻冷启动照常查，**没有被上一次失败吞掉 24 小时**。
- [x] 手动 Check for updates 在飞行模式下说 `Check failed: ...` —— 2026-08-22
      验过。手动路径必须给确定答复，不能跟自动路径一样闷着。

## 阶段 3 · 正向用例（取消 prerelease）

```bash
gh release edit updatetest-v1.0.1 --prerelease=false
```

设置页点一次 **重置**，然后冷启动。

- [x] **弹出提示** —— 2026-08-22 验过，标题 `Update available: 1.0.1`，
      说明文字、Later / Update 都正常。
- [x] **点「更新」跳系统浏览器** —— 2026-08-22 验过，Chrome 打开并开始下载。
      **`<queries>` 那条 https VIEW intent 由此确认有效**。

      顺带记一笔真实摩擦：Chrome 对 APK 会先弹一道
      「File might be harmful / Download anyway」，每个用户都躲不开，
      除非改成应用内下载 + FileProvider 安装。
- [x] **下到的是 arm64-v8a 那个包** —— 2026-08-22 验过，Chrome 的下载确认框上
      写的是 `app-arm64-v8a-release.apk`（18.38 MB）。
- [x] **覆盖安装成功** —— 2026-08-22 验过，设置页 Version 变成 `1.0.1`。
      **「发布用的 keystore 跟已装那版一致」由此得到唯一的实证**。
- [x] **不再重复弹** —— 2026-08-22 验过。
- [x] **「稍后」会被记住** —— 2026-08-22 验过：弹窗点 Later 后，不 Reset
      直接冷启动不再弹。
- [x] **应用锁在前** —— 2026-08-22 验过：先手势锁，画对之后才看到更新弹窗。

      第一次跑这条时解锁后什么都没有，一度当成 bug。真因是**上一条测试点过
      「Later」，1.0.1 已被记进「已忽略的版本」**，没先 Reset 就再测，
      `checkOnLaunch` 直接返回 null——压根没东西可弹。这条测试之前必须：

      1. **Reset**（清掉「上次检查时间」和「已忽略版本」）
      2. **点一次 Check for updates 确认看得到 `Version x 
         is available`**——手动路径不写时间戳、也不看「已忽略版本」，
         既能证明「这次确实有东西可弹」，又不会把冷启动的额度提前用掉
      3. 再开应用锁、设手势，**中间不要冷启动**（任何一次冷启动都会把额度用掉）

### 这条链路原本没有任何自动化覆盖

`PendingUpdate` 当初被拎出来就是为了让「更新提示要等锁屏让路」可测，但测试
只测到了它自己——测不到它跟 `LockGate`、`showDialog`、`navigatorKey` 拼起来
之后还成不成立，**而真机上出问题的正是这一层**。

补不上 app 级测试的直接原因：`PakeApp` 挂着 `flutter_inappwebview`，widget
test 里 `InAppWebViewPlatform.instance` 是 null，一 build 就断言失败。
`test/app_update_test.dart` 用一份跟 `app.dart` 结构逐字对齐、只把 WebView
换成一段文字的骨架绕开它，并用 `Future.delayed` 把真机时序钉死：锁屏先起来、
网络 1 秒后才回来。不给这个延迟的话假 fetch 在第一帧之前就完成了，`locked`
还是 false，走的是「没锁」那条路径，等于什么都没测到。

**`app.dart` 改了结构而这份骨架不跟，这条测试就会变成自欺欺人。**

### 2026-08-22 踩到的一个假警报：GitHub API 有 ~60 秒缓存

取消 prerelease 勾选后**立刻**冷启动，没弹提示。查了半天网络、权限、解析，
最后发现是未登录的 `api.github.com` 响应带 CDN 缓存（约 60 秒）——app 拿到的
还是 `prerelease: true` 的旧响应。等过窗口再冷启动就正常。

不是 bug，但**直接影响 README 里写的灰度流程**：验完 prerelease 取消勾选后，
最长要等一分钟用户才查得到。测试时也别比缓存跑得快。

## 阶段 4 · 4kvm 上的真实端到端

前面全过之后，在真 app 上跑一遍，主要验证的是「已装用户能不能覆盖安装」。

- [ ] 给 `presets/4kvm.json` 补上 `"version": "1.0.0"`（现在缺，靠默认值撑着，
      发版时容易搞不清发的是哪个版本）。顺带决定 url 要不要从被墙的
      `www.4kvm.net` 换成 `www.4kvm.site`。
- [ ] build + 装到真机 + 确认页面能开。
- [ ] bump 到 `1.0.1`，build，`pakem release`，**立刻 `gh release edit --prerelease`**。
- [ ] 手机上重置 + 冷启动 → 不弹（prerelease 生效，真实用户此刻是安全的）。
- [ ] 手动确认那个 release 的 asset 列表和说明都对。
- [ ] 取消 prerelease → 重置 + 冷启动 → 弹 → 下载 → 覆盖安装成功。

## 收尾

- [x] 删掉测试 app 的 release 和 tag（2026-08-22 已做，远端已无 `updatetest` tag）：

      ```bash
      gh release delete updatetest-v1.0.0 --yes --cleanup-tag
      gh release delete updatetest-v1.0.1 --yes --cleanup-tag
      adb uninstall com.pake.updatetest
      ```

- [ ] 4kvm 那个测试版本要么留着当正式 1.0.1，要么同样删掉。
      **一旦取消过 prerelease 就可能已经有人下过了**，删 release 不会把它撤回来。
