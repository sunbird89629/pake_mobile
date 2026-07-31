import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 左上角 44×44 的透明手势区，长按 1.5 秒打开设置。
///
/// 必须在 Flutter 层而非网页内：`InAppWebView` 吞掉所有触摸事件，
/// 且网页白屏时用户仍须能进设置改回 URL，否则 app 变砖。
class EscapeHatch extends StatelessWidget {
  const EscapeHatch({super.key, required this.onTriggered});

  final VoidCallback onTriggered;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      // GestureDetector.onLongPress 写死 500ms，太容易误触，
      // 所以这里下沉到 RawGestureDetector 自定义时长。
      child: RawGestureDetector(
        // translucent 而不是 opaque：opaque 会让命中测试在这里停住，底下的
        // `InAppWebView` 一个事件都收不到——而左上角 44×44 正是移动站点放
        // 汉堡菜单和返回按钮的地方，那些按钮会变成完全点不动。
        // translucent 仍然把自己加进命中结果（长按照样识别），只是不拦截
        // 后面的目标。
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 1500),
                ),
                (recognizer) => recognizer.onLongPress = onTriggered,
              ),
        },
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
