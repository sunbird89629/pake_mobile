import 'dart:math' as math;

import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter/material.dart';

import 'pattern_code.dart';

/// 弹出设置手势图案的对话框。返回新图案的 SHA-256 摘要；取消返回 `null`。
///
/// 修改图案走的也是这里，不要求先画旧图案——人能站在设置页里，说明刚才
/// 已经解过锁了。
Future<String?> showPatternDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const PatternDialog());

class PatternDialog extends StatefulWidget {
  const PatternDialog({super.key});

  @override
  State<PatternDialog> createState() => _PatternDialogState();
}

class _PatternDialogState extends State<PatternDialog> {
  /// 第一笔。为空表示还没画第一笔。
  List<int>? _first;
  String? _error;

  void _entered(List<int> pattern) {
    final first = _first;

    if (first == null) {
      // 第一笔就先卡长度，别等画完第二笔才告诉人「太短」。
      final error = validatePattern(pattern, pattern);
      setState(() {
        _error = error;
        // 必须拷一份。`PatternLock` 传进来的是它内部那个 list 本身，回调
        // 返回后它会就地清空——存引用的话，等第二笔画完时 `_first` 已经
        // 变成空列表了，两笔永远对不上。
        _first = error == null ? List.of(pattern) : null;
      });
      return;
    }

    final error = validatePattern(first, pattern);
    if (error != null) {
      // 不匹配就退回第一步重来，而不是留着一笔让人只补第二笔——那样人分不清
      // 自己在画第几笔。
      setState(() {
        _error = error;
        _first = null;
      });
      return;
    }
    Navigator.of(context).pop(hashPattern(pattern));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    // 用裸 Dialog 而不是 AlertDialog：AlertDialog 会去量内容的固有尺寸，而
    // 下面这个 LayoutBuilder 给不出固有尺寸，直接 assert。
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 网格必须是正方形——按盒子宽高各分三份，长方形会把格子拉扁，
            // 手指落点和视觉中心就对不上。边长不能写死：窄屏上宽度先到顶，
            // 宽屏上高度先到顶，取两者与 260 的最小值，两个方向都不撑破。
            // 96 是标题、错误行和按钮占掉的高度。
            final side = math.min(
              math.min(constraints.maxWidth, constraints.maxHeight - 96),
              260.0,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _first == null ? 'Draw a new pattern' : 'Draw it again',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: side,
                  height: side,
                  // 不要给它换 key。组件一笔画完会自己清空高亮，而换 key 会
                  // 重建 Element——新实例要等布局后的一帧才把各格子的位置报
                  // 上去，紧接着落下的第二笔一个格子都收不到，永远匹配不上。
                  child: PatternLock(
                    width: 3,
                    height: 3,
                    linkageConfig: PatternLockLinkageConfig.distance(3),
                    onEntered: _entered,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
