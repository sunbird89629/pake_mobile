import 'package:flutter/foundation.dart';

import 'update_check.dart';

/// 「查到了新版，但得等锁屏让路」这件事。
///
/// 拎出来是为了能测：`LockGate` 挂在 `MaterialApp.builder` 上、盖在 navigator
/// 之上，锁着的时候弹 dialog 会被它盖住——弹是弹了，用户看不见，而「每个
/// 版本只弹一次」的额度已经消费掉了。这个 bug 只在**开了应用锁**的冷启动
/// 路径上出现，跑 widget test 的人不会去开锁。
class PendingUpdate {
  PendingUpdate({required this.locked, required this.onReady});

  /// 锁定状态的唯一真相，由 `PakeApp` 持有、`LockGate` 写入。
  final ValueListenable<bool> locked;
  final void Function(UpdateInfo info) onReady;

  UpdateInfo? _info;

  /// 没锁就立刻回调，锁着就攥住等解锁。
  void offer(UpdateInfo info) {
    _info = info;
    if (locked.value) {
      locked.addListener(_flush);
    } else {
      _flush();
    }
  }

  void _flush() {
    if (locked.value) return;
    locked.removeListener(_flush);

    final info = _info;
    if (info == null) return;
    // 先清空再回调：同一个版本只该走一次，哪怕监听器被重复触发。
    _info = null;
    onReady(info);
  }

  void dispose() => locked.removeListener(_flush);
}
