import 'package:flutter/material.dart';

import '../runtime_config.dart';
import 'lock_screen.dart';

/// 应用锁的闸门：决定什么时候用 [LockScreen] 盖住 [child]。
///
/// 挂在 `MaterialApp.builder` 上，位置在 Navigator 之上——遮罩因此能盖住
/// 任何已经 push 出来的路由（比如设置页）。包 `home` 是不行的：人在设置页
/// 里切后台再回来，锁屏会被设置页盖住，等于没锁。
class PinGate extends StatefulWidget {
  const PinGate({
    super.key,
    required this.config,
    required this.child,
    required this.locked,
    this.timeout = const Duration(seconds: 30),
  });

  final RuntimeConfig config;
  final Widget child;

  /// 锁定状态的唯一真相，由外面（`PakeApp`）持有、这里独家写入。
  ///
  /// 之所以不留成 `_PinGateState` 的私有 bool：`WebViewPage` 接管了系统返回
  /// 键，锁着的时候必须让返回键失效，否则会去调下面那个被遮住的 WebView 的
  /// `goBack()`——用户看不见，解锁后发现页面变了。`LockScreen` 自己那个
  /// `PopScope(canPop: false)` 拦不住，它在 Navigator 之上，
  /// `ModalRoute.of` 返回 null。
  final ValueNotifier<bool> locked;

  /// 后台停留多久算「离开过」。留成参数只是为了测试能传个很短的值——
  /// 设置页里不暴露它。
  final Duration timeout;

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    // 在第一次 build 之前写，此时还没有 ValueListenableBuilder 在听，不会
    // 触发「build 期间通知监听者」。
    widget.locked.value =
        widget.config.appLockEnabled && widget.config.pinCode != null;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive 在下拉通知栏、来电横幅、iOS 应用切换器出现时就触发——用它
    // 等于划一下通知栏就开始计时。paused 才是真进了后台。
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // 时间戳只能用一次：不管后面配置检查过不过，先读出来清掉。放在配置
    // 检查之后会漏——锁关着的时候一次 resumed 被配置检查挡住返回，时间戳
    // 留在原地；之后哪怕全程在前台把锁打开，下一次 resumed 也会拿这个陈旧
    // 时间戳去算差，把人错误地锁在外面。
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;

    // 每次都读实时值：设置页刚关掉锁，这里立刻就能看到，不需要通知机制。
    final config = widget.config;
    if (!config.appLockEnabled || config.pinCode == null) return;

    // 后台里 Timer 不保证继续跑（进程可能被冻结），只能记时间戳、回来算差。
    if (DateTime.now().difference(pausedAt) >= widget.timeout) {
      widget.locked.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.locked,
      builder: (context, locked, _) => _build(context, locked: locked),
    );
  }

  Widget _build(BuildContext context, {required bool locked}) {
    final pin = widget.config.pinCode;
    final showLock = locked && pin != null;

    // 用 Stack 盖住而不是直接 return LockScreen 换掉：child 是整棵
    // Navigator 子树（WebView、路由栈都挂在里面），换掉就等于卸载重建，
    // 路由栈、滚动位置、登录态全部丢——锁屏只能是盖在上面。被锁的时候用
    // Offstage 让 child 既不绘制也不响应点击（find.text 等默认查找也会
    // 跳过 offstage 节点，不影响断言）；child 本身永远留在树里不被换掉。
    return Stack(
      children: [
        Offstage(offstage: showLock, child: widget.child),
        if (showLock)
          Positioned.fill(
            child: LockScreen(
              pinCode: pin,
              appName: widget.config.buildTime.name,
              onUnlocked: () {
                _pausedAt = null;
                widget.locked.value = false;
              },
            ),
          ),
      ],
    );
  }
}
