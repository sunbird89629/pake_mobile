import 'package:flutter/material.dart';

/// 浮在网页之上的底部胶囊：后退、刷新、设置。
///
/// 删掉 `EscapeHatch` 之后，这里的 ⚙ 和错误页那个按钮是仅剩的两个设置入口。
/// **因此这条栏绝不能做成可配置关闭**——用户在设置页把它关掉、退出设置，就
/// 再也没有任何入口能打开设置，app 只能卸载重装。要加开关就必须把
/// `EscapeHatch` 一起加回来，二选一。
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.visible,
    required this.canGoBack,
    required this.onBack,
    required this.onReload,
    required this.onOpenSettings,
  });

  /// 显示还是隐藏。隐藏时向下滑出屏幕，并停止接收点击。
  final bool visible;

  /// 网页还有没有可回退的历史。没有时后退按钮变灰——它必须跟系统返回键
  /// 长得不一样：返回键在没历史时退出 app，一个工具栏上的「←」把 app 关掉
  /// 太吓人，什么都不做又像卡死了。灰掉是唯一说得通的第三种答案。
  final bool canGoBack;

  final VoidCallback onBack;
  final VoidCallback onReload;
  final VoidCallback onOpenSettings;

  /// 胶囊高度。也被 `barStateAfterScroll` 当作「算不算在页面顶部」的阈值。
  static const height = 48.0;

  /// 不透明深色，跟顶部状态栏那条留白的底色呼应。
  ///
  /// 不用半透明毛玻璃：网页内容五花八门，半透明底上的图标在浅色网页上会糊
  /// 掉；而且 `BackdropFilter` 叠在 `PlatformView` 之上有已知的性能和渲染
  /// 问题。
  static const _background = Color(0xFF1C1C1E);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 位移后的命中测试理论上会跟着变换走，但这条栏盖的是网页的可点区域，
      // 不赌 PlatformView 在 FractionalTranslation 下的命中行为。显式忽略。
      ignoring: !visible,
      child: AnimatedSlide(
        // 给 2 而不是 1：胶囊坐在手势条之上、离底边有一段距离，只移动 1 倍
        // 自身高度还有一半挂在缝里。多出来的行程被 Stack 默认的
        // Clip.hardEdge 裁掉，看不见。
        offset: visible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Center(
          child: Material(
            color: _background,
            shape: const StadiumBorder(),
            elevation: 6,
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _button(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onPressed: canGoBack ? onBack : null,
                  ),
                  _button(
                    icon: Icons.refresh,
                    tooltip: 'Reload',
                    onPressed: onReload,
                  ),
                  _button(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onPressed: onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) => IconButton(
    icon: Icon(icon),
    tooltip: tooltip,
    onPressed: onPressed,
    color: Colors.white,
    disabledColor: Colors.white24,
  );
}
