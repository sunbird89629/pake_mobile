---
name: app-screenshot
description: 给 pake_mobile 的预设 app（4KVM / DADATU / YouTube）截真机图并更新仓库文档。流程：从 GitHub Releases 下载该 app 的最新正式版 APK → 安装到 Pixel（39111FDJH00D47）→ 启动并截图 → 缩放后存 docs/images/ 并更新 README。当用户说「截 app 的图」「更新 README 里的截图」「给 4kvm / 哒哒兔 / youtube 截图」「预设 app 的图片要换新的」时使用，即使没提「最新版」——README 展示的应该是当前正式版。
---

# 预设 app 截图

给一个或多个预设 app 截真机图，替换仓库文档里的旧图。README「用现成的
app」一节的截图展示的是**当前正式版**，版本 bump 后旧图就失真了，所以
这个流程的第一件事是下载最新版，而不是截手机上装的旧包。

## 确定目标 app

从用户的话里找 app：`4kvm` / `dadatu` / `youtube`（也认「哒哒兔」）。没
指定就三个全做。

对每个目标 app，读 `presets/<slug>.json` 拿两样东西：

- `bundleId`（如 `com.pake.fourkvm`）——安装、启动要用，tag 前缀取它
  **末段**（`fourkvm`）
- 顺带核对 README「用现成的 app」表格里该 app 的下载链接 tag，如果落后
  于最新正式版，截图完要把它一起 bump

## 前置检查

```bash
adb devices
gh auth status
```

- 设备 `39111FDJH00D47` 必须在线。`adb devices` 列表里可能有
  `_adb-tls-connect` 结尾的无线别名，一律用 `39111FDJH00D47` 这个串号。
- 屏幕锁状态：`adb shell dumpsys window | grep -E "mScreenLocked|mCurrentFocus"`。
  **锁屏就停下来让用户解锁，绝不猜 PIN**——之前有过设备锁屏导致截屏全黑。
- `gh` 要已登录（下载 release 用）。

## 每个 app 的流程

```bash
# 1. 找最新正式版 tag：按前缀筛，跳过 prerelease（README 展示的是正式版）
gh release list --limit 50 | grep '<slug>-v' | grep -v Pre-release

# 2. 下载 arm64 APK 到临时目录（临时文件，别放仓库里）
mkdir -p /tmp/app-screenshot/<slug>
gh release download <tag> --pattern '*arm64-v8a*' -D /tmp/app-screenshot/<slug>

# 3. 安装（覆盖装，-r 允许降级）
adb -s 39111FDJH00D47 install -r /tmp/app-screenshot/<slug>/<apk>

# 4. 启动并等页面加载
adb -s 39111FDJH00D47 shell monkey -p <bundleId> -c android.intent.category.LAUNCHER 1
sleep 10   # WebView 加载站点要时间，截早了是白屏
```

等 10 秒后再截第一张，截完自己看一眼：如果还是白屏或加载中，再等几秒重
截。影视站首页偶尔弹验证/广告，没关系——README 要的是 app 形态，首屏
内容是什么不重要。

```bash
# 5. 截图并验证非空白（几 KB 或纯色就是没截好）
adb -s 39111FDJH00D47 exec-out screencap -p > /tmp/app-screenshot/<slug>/raw.png
sips -g pixelWidth -g pixelHeight /tmp/app-screenshot/<slug>/raw.png

# 6. 缩放到 400px 宽，覆盖仓库里的旧图
sips --resampleWidth 400 /tmp/app-screenshot/<slug>/raw.png --out docs/images/<slug>.png
```

不直接存全尺寸：手机截图 1080×2400，放进 README 一张就占一屏。

## 更新文档

- 图片覆盖 `docs/images/<slug>.png` 后，README 若已引用该路径就不用动
  markdown（同名覆盖自动生效）。
- 若 README 还没引用（新图），按现有排布加 markdown——三个 app 的截图放
  同一行连续引用，GitHub 渲染时自动并排。
- **检查版本号**：README 表格的下载链接是 `<slug>-v<version>` 的 tag，若
  步骤 1 找到的最新 tag 更新，把链接和文字一起 bump，别让链接指着旧版。
- 顺手核对截图内容与文档描述是否还一致（比如 app 主页大变样），不一致时
  提醒用户，不自行改文字结论。

## 注意事项

- 截图任务只用 `/tmp/app-screenshot/` 作临时区，**不要碰 `~/.pake/out/`**
  （用户明确说过那下面的产物不清）。
- 设备锁屏时停下，让用户解锁，不要尝试任何绕过手段。
- 每装一个 app 截完图，接着做下一个；全部完成后向用户汇报每张图存到了
  哪里、README 改了哪几行。
