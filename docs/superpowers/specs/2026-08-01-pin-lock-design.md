# 应用 PIN 锁设计

给 pake 壳加一道 PIN 码锁：启动时、以及后台停留超过 30 秒回到前台时，用四位数字锁挡在网页之前。
默认关闭，在设置页里开启并设置 PIN。

## 决策记录

| 问题 | 结论 |
|---|---|
| PIN 从哪来 | 运行期，设置页里设。构建期 `pake.json` 不参与——同一个 APK 每个人自己定，改 PIN 不用重新构建 |
| 何时锁 | 冷启动 + 后台超过 30 秒回前台 |
| 忘了 PIN | 锁屏封死，没有后门。只能清数据或重装 |
| PIN 怎么存 | 明文 `int`，禁 0 开头 |
| 超时时长 | 常量 30 秒，不进设置页 |

两条需要留意的：

**锁屏封死意味着 EscapeHatch 被盖住。** README 把「长按左上角进设置」写成刻意的防砖设计——白屏时也能进去改 URL。锁屏在它之上，忘记 PIN 就没有恢复路径了。这是明确选择的结果，不是疏漏。

**明文存 PIN。** 威胁模型是「别人拿起我的手机」，不是取证分析；root / 越狱能直接读到 `get_storage` 的 JSON。换成哈希的代价是 `PinLockScreen` 的比对在 widget 内部，必须拿到明文 `int` 才能用，改哈希就得放弃它自带的错误红点反馈、自己重做一套。

禁 0 开头是因为 `int.parse("0123") == 123`——允许的话，`0123` 和 `123` 会是同一个 PIN。

## 架构

```
packages/pake_config/lib/src/runtime_keys.dart      改：+2 个键
packages/pake_shell/lib/src/runtime_config.dart     改：+2 组读写、reset 补键
packages/pake_shell/lib/src/app.dart                改：MaterialApp.builder 挂 PinGate
packages/pake_shell/lib/src/lock/pin_gate.dart      新：状态机 + 生命周期
packages/pake_shell/lib/src/lock/lock_screen.dart   新：PIN 界面
packages/pake_shell/lib/src/debug_drawer.dart       改：+「应用锁」区块
packages/pake_shell/pubspec.yaml                    改：+ pin_lock_screen ^1.0.1
```

### 挂载点

```dart
MaterialApp(
  navigatorKey: _navigatorKey,
  builder: (context, child) => PinGate(config: widget.config, child: child!),
  home: Stack([WebViewPage, EscapeHatch]),
)
```

挂 `builder` 而不是包 `home`。设置页是 `push` 出来的路由——包 `home` 的话，人在设置页里切后台再回来，锁屏会被设置页盖住，等于没锁。`builder` 位于 Navigator 之上，遮罩盖住一切路由，也盖住 `EscapeHatch`。

`PinGate` 对外只有一个接口：给它一个 child，它决定显示 child 还是锁屏。WebView 始终留在树里——被遮住而不是被卸载，解锁后页面状态、滚动位置、登录态都还在。

## PinGate 状态机

`StatefulWidget` + `WidgetsBindingObserver`，全部状态两个字段：

```dart
bool _locked = config.appLockEnabled;   // 冷启动即锁
DateTime? _pausedAt;

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _pausedAt = DateTime.now();
  } else if (state == AppLifecycleState.resumed) {
    if (!config.appLockEnabled || config.pinCode == null) return;
    final away = DateTime.now().difference(_pausedAt ?? DateTime.now());
    if (away >= timeout) setState(() => _locked = true);
  }
}
```

`timeout` 是构造参数，默认 30 秒，标 `@visibleForTesting`——测试里传 100ms 就能测超时，不必注入伪时钟。

**用 `paused` 不用 `inactive`。** `inactive` 在下拉通知栏、来电横幅、iOS 应用切换器出现时就触发，用它等于划一下通知栏就开始计时。

**用 `DateTime` 差值不用 `Timer`。** app 在后台被系统冻结时 `Timer` 不保证继续跑，30 秒可能永远不到。记时间戳、回前台算差值是唯一可靠的做法。

**不需要通知机制。** `RuntimeConfig` 读 `get_storage` 是同步的，`resumed` 时直接读实时值。设置页关掉应用锁，下次 resume 读到 `false` 就不锁，立即生效。

**开启开关不立刻弹锁屏。** 用户刚设完 PIN，马上把他锁在外面很蠢。开关只影响下次冷启动 / 下次超时。

**`pinCode == null` 无条件放行。** 防御性的：一个残缺的存储状态不该能把 app 变砖。

## 配置层

`RuntimeKeys` 沿用 `pake.` 前缀：

```dart
static const appLockEnabled = 'pake.appLockEnabled';
static const pinCode = 'pake.pinCode';
```

`RuntimeConfig` 加两组读写。`appLockEnabled` 默认 `false`——这是个网页壳，多数站点不需要锁，默认开会让现有 preset 的用户莫名其妙被挡在外面。`pinCode` 是 `int?`，读到非 int 当 null，沿用现有 `_readString` / `_readBool` 的容错风格。

两个键都进 `reset()`。重置 = 清空运行期层，把应用锁单独留下语义不一致；能按到重置按钮的人必然已经解锁过，不构成后门。

## 设置页

`DebugDrawer` 新增「应用锁」区块，两行：

- `SwitchListTile`「应用锁」。**关→开**：弹对话框设 PIN，成功才真正打开开关，取消则开关回弹。**开→关**：直接关并清掉 `pinCode`，不二次验证——人能站在设置页里，说明刚才已经输对过 PIN。
- 开启状态下多一行「修改 PIN」，复用同一个设 PIN 对话框和同一套校验，不要求先输旧 PIN。

设 PIN 用 `AlertDialog` + 两个数字 `TextField`（新 PIN / 确认），不用 `PinLockScreen` 键盘：那个 widget 的 API 是「给我正确值、我来比对」的匹配模式，设新 PIN 时没有正确值可传，硬套要塞占位值再从 `onPinChanged` 里捞输入。

校验三条，任一不满足就 `errorText` 提示、不关闭对话框：

1. 4 位数字
2. 首位非 0
3. 两次输入一致

## 锁屏界面

`lock_screen.dart` 是纯展示组件，入参 `pinCode` 和 `onUnlocked` 回调：

```dart
PinLockScreen(
  correctPin: pinCode,
  pinLength: 4,
  onPinMatched: (_) => onUnlocked(),
)
```

外面套 `PopScope(canPop: false)` 挡返回键，套 `SafeArea` + 可滚动容器——`PinLockScreen` 内部是固定高度的 `Column`，小屏设备会溢出。配色跟 `DebugDrawer` 现有风格走，顶部显示 app 名。

## 不做

**锁屏时暂停 WebView 音频。** 4KVM / DADATU 都是影视站，锁上了声音还在响。要停得往 `WebViewPage` 开一个 `evaluateJavascript` 暂停所有 `<video>` 的新接口，跨出本次范围；「锁屏继续听」也未必是 bug。

**遮挡 Android 最近任务列表的缩略图。** 锁住了，但任务切换器里的预览仍是网页内容。挡它需要 `FLAG_SECURE`，那是 `privacy_screen` / `app_security_lock` 的能力，`pin_lock_screen` 给不了。

## 测试

新增 `test/pin_gate_test.dart`，六个 case：

1. 应用锁关闭 → 直接显示 child
2. 应用锁开启 → 冷启动显示锁屏
3. `pinCode` 为 null → 放行（防砖回归）
4. 输对 PIN → 显示 child
5. resume 且离开时长未到 → 不锁
6. resume 且离开超过 timeout → 锁

生命周期用 `tester.binding.handleAppLifecycleStateChanged(...)` 驱动，超时用构造参数传 100ms。`RuntimeConfig` 的构造沿用现有 `runtime_config_test.dart` 的 GetStorage 初始化模式。

`RuntimeConfig` 新增的两组读写补进 `runtime_config_test.dart`：默认值、写入回读、`reset()` 后回到默认。
