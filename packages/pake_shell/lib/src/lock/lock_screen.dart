import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter/material.dart';

import 'pattern_code.dart';

/// 手势锁界面。纯展示——什么时候该显示它，由 `LockGate` 决定。
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.patternHash,
    required this.appName,
    required this.onUnlocked,
  });

  /// 正确图案的 SHA-256 摘要。这里拿不到、也不需要图案本身。
  final String patternHash;
  final String appName;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _wrong = false;

  void _check(List<int> pattern) {
    if (hashPattern(pattern) == widget.patternHash) {
      widget.onUnlocked();
      return;
    }
    setState(() => _wrong = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 锁屏不是路由，返回键会穿透到底下被遮住的页面上去导航。
    //
    // 注意：这个 `PopScope` 挂在 Navigator **之上**（`LockGate` 在
    // `MaterialApp.builder` 里），`ModalRoute.of` 返回 null，它其实注册不上、
    // 一行作用都没有。真正挡住返回键的是 `WebViewPage` 里那个读 `locked` 的
    // `PopScope`。留着它只是表意，不要依赖——见
    // `docs/superpowers/specs/2026-08-18-bottom-bar-design.md`。
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 12),
                  Text(widget.appName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    _wrong ? 'Wrong pattern' : 'Draw your pattern',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _wrong ? theme.colorScheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 280,
                    height: 280,
                    child: PatternLock(
                      width: 3,
                      height: 3,
                      // 默认 maxLinkDistance 是 1，只能连相邻格——3×3 上这会
                      // 把可用图案砍掉一大半。放开到 3（角到角约 2.83）才是
                      // 系统锁那样的自由连线。
                      linkageConfig: PatternLockLinkageConfig.distance(3),
                      onEntered: _check,
                      // 重新落笔就把上一次的错误提示清掉，否则画对了红字还挂着。
                      onUpdate: (_) {
                        if (_wrong) setState(() => _wrong = false);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
