import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pake_shell/src/widgets/action_button.dart';

/// 浮在网页之上的底部工具栏：后退、刷新、设置。
///
/// 删掉 `EscapeHatch` 之后，这里的 ⚙ 和错误页那个按钮是仅剩的两个设置入口。
/// **因此这条栏绝不能做成可配置关闭**——用户在设置页把它关掉、退出设置，就
/// 再也没有任何入口能打开设置，app 只能卸载重装。要加开关就必须把
/// `EscapeHatch` 一起加回来，二选一。
///
/// 尺寸与配色见 `docs/superpowers/specs/2026-08-18-bottom-bar-design.md`
/// 里链接的设计画布。
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

  /// 栏高。也被 `barStateAfterScroll` 当作「算不算在页面顶部」的阈值。
  static const height = 64.0;

  /// 固定宽度。三个 56 的触控格加起来 168，剩下的 40 由 `spaceEvenly` 均分
  /// 成四个 10 的间隙——按钮不抱团，也不贴边。
  static const _width = 208.0;

  static const _radius = 18.0;
  static const _tapTarget = 56.0;

  /// 毛玻璃底。半透明深色 + 背后模糊，深色站点上比一块实心方块轻。
  ///
  /// 只有这一套配色，没有跟随网页深浅的逻辑：壳拿不到可靠信号判断当前页面
  /// 是深是浅（唯一能读的是网页的 `<meta name="theme-color">`，很多站点根本
  /// 不给）。目标站点多是深色，先钉死深色玻璃 + 白图标；浅色站点上对比度会
  /// 下降，这是选毛玻璃就得接受的代价。
  static const _glass = Color(0x8C1C1C1E);
  static const _glassEdge = Color(0x26FFFFFF);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 位移后的命中测试理论上会跟着变换走，但这条栏盖的是网页的可点区域，
      // 不赌 PlatformView 在 FractionalTranslation 下的命中行为。显式忽略。
      ignoring: !visible,
      child: AnimatedSlide(
        // 给 2 而不是 1：栏坐在手势条之上、离底边有一段距离，只移动 1 倍
        // 自身高度还有一半挂在缝里。多出来的行程被 Stack 默认的
        // Clip.hardEdge 裁掉，看不见。
        offset: visible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Center(
          child: DecoratedBox(
            // 投影必须挂在 ClipRRect 外面——里面画的会被裁掉。
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 3),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              // BackdropFilter 必须被裁剪包住，否则它会去模糊整个屏幕。
              borderRadius: BorderRadius.circular(_radius),
              child: BackdropFilter(
                // 叠在 InAppWebView 这种 PlatformView 之上有已知的性能风险，
                // 滚动时最容易暴露。真机掉帧的话先降这个 sigma。
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: _width,
                  height: height,
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(color: _glassEdge),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ActionButton(
                        tapTarget: _tapTarget,
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onPressed: canGoBack ? onBack : null,
                      ),
                      ActionButton(
                        tapTarget: _tapTarget,
                        icon: Icons.refresh,
                        tooltip: 'Reload',
                        onPressed: onReload,
                      ),
                      ActionButton(
                        tapTarget: _tapTarget,
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
        ),
      ),
    );
  }
}
