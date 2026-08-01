import 'package:flutter/material.dart';
import 'package:pin_lock_screen/pin_lock_screen.dart';

/// PIN 锁界面。纯展示——什么时候该显示它，由 `PinGate` 决定。
class LockScreen extends StatelessWidget {
  const LockScreen({
    super.key,
    required this.pinCode,
    required this.appName,
    required this.onUnlocked,
  });

  final int pinCode;
  final String appName;
  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 锁屏不是路由，返回键会穿透到底下被遮住的页面上去导航。canPop: false
    // 把它挡住。
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            // PinLockScreen 内部是固定高度的 Column，小屏设备会溢出。
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 12),
                  Text(appName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 32),
                  PinLockScreen(
                    correctPin: pinCode,
                    pinLength: 4,
                    onPinMatched: (_) => onUnlocked(),
                    disableDotColor: theme.disabledColor,
                    filledPinDotColor: theme.colorScheme.primary,
                    wrongPinDotColor: theme.colorScheme.error,
                    gapBtwDotsAndNumPad: 40,
                    buttonSize: const Size(72, 72),
                    buttonBorderRadius: 36,
                    buttonBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                    buttonForegroundColor: theme.colorScheme.onSurface,
                    deleteWidget: const Icon(Icons.backspace_outlined),
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
