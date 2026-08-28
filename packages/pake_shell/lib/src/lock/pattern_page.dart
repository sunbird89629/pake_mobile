import 'package:better_pattern_lock/better_pattern_lock.dart';
import 'package:flutter/material.dart';

import 'pattern_code.dart';

/// 打开设置手势图案的页面。返回新图案的 SHA-256 摘要；退出返回 `null`。
///
/// 是一个整页而不是对话框：对话框里那块网格只能塞进 260 见方，比锁屏上真正
/// 画图案的那块（280）还小，人在小格子上设的图案，回头在大格子上解要重新
/// 适应。整页还顺带把「取消」交还给了系统返回键。
///
/// 修改图案走的也是这里，不要求先画旧图案——人能站在设置页里，说明刚才已经
/// 解过锁了。
Future<String?> showPatternPage(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const PatternPage()));

class PatternPage extends StatefulWidget {
  const PatternPage({super.key});

  @override
  State<PatternPage> createState() => _PatternPageState();
}

class _PatternPageState extends State<PatternPage> {
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

    return Scaffold(
      // 返回箭头就是「取消」：没画完两笔就退出，`showPatternPage` 拿到 null，
      // 调用方什么都不写。
      appBar: AppBar(title: const Text('Set pattern')),
      body: SafeArea(
        child: Center(
          // 矮屏上 280 的网格加上面那几行会顶出去，滚动兜住。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pattern, size: 56),
                const SizedBox(height: 12),
                Text(
                  _first == null ? 'Draw a new pattern' : 'Draw it again',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                // 提示和报错共用这一行——同时只可能有一个成立，分成两行的话
                // 报错时上面那句正确的提示还挂着，读起来像在自相矛盾。
                Text(
                  error ??
                      'Connect at least $minPatternLength dots. '
                          'The direction matters.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: error == null ? null : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  // 跟锁屏同一个尺寸：在这儿画顺手的图案，解锁时手感才一样。
                  width: 280,
                  height: 280,
                  // 不要给它换 key。组件一笔画完会自己清空高亮，而换 key 会
                  // 重建 Element——新实例要等布局后的一帧才把各格子的位置报
                  // 上去，紧接着落下的第二笔一个格子都收不到，永远匹配不上。
                  child: PatternLock(
                    width: 3,
                    height: 3,
                    linkageConfig: PatternLockLinkageConfig.distance(3),
                    onEntered: _entered,
                    // 重新落笔就把上一次的报错清掉，跟锁屏一致，否则画对了
                    // 红字还挂着。
                    onUpdate: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
