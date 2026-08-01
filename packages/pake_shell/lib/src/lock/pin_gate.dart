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
    this.timeout = const Duration(seconds: 30),
  });

  final RuntimeConfig config;
  final Widget child;

  /// 后台停留多久算「离开过」。留成参数只是为了测试能传个很短的值——
  /// 设置页里不暴露它。
  final Duration timeout;

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> with WidgetsBindingObserver {
  late bool _locked =
      widget.config.appLockEnabled && widget.config.pinCode != null;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
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
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.config.pinCode;
    if (!_locked || pin == null) return widget.child;

    return LockScreen(
      pinCode: pin,
      appName: widget.config.buildTime.name,
      onUnlocked: () => setState(() {
        _locked = false;
        _pausedAt = null;
      }),
    );
  }
}
