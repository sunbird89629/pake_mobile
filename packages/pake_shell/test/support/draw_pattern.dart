import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在屏幕上唯一那块 [PatternLock] 里画一笔，按格子序号连线。
///
/// 序号是 3×3 网格里从左到右、从上到下的位置（0..8），跟组件回调给出的
/// `List<int>` 是同一套编号。
///
/// 前提：那块 [PatternLock] 的盒子是正方形。网格按盒子宽高各分三份，盒子
/// 是长方形的话这里算出来的中心点就会偏出格子——UI 侧一律给方盒子。
///
/// 手势必须逐点 `moveTo` 而不是一次 `dragFrom`：组件靠指针经过格子来累积
/// 图案，一步跨到终点的话中间的格子一个都不会被点亮。
Future<void> drawPattern(WidgetTester tester, List<int> cells) async {
  // 先settle：组件要等布局完成后的一帧才把各格子的位置报上去，紧接着
  // pumpWidget 就画的话，指针经过时它手里一个格子都还没有，收到的图案是空的。
  await tester.pumpAndSettle();

  final rect = tester.getRect(find.byType(PatternLock));

  Offset centerOf(int cell) {
    final cellW = rect.width / 3;
    final cellH = rect.height / 3;
    return rect.topLeft +
        Offset((cell % 3 + 0.5) * cellW, (cell ~/ 3 + 0.5) * cellH);
  }

  final gesture = await tester.startGesture(centerOf(cells.first));
  await tester.pump();
  for (final cell in cells.skip(1)) {
    await gesture.moveTo(centerOf(cell));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}
