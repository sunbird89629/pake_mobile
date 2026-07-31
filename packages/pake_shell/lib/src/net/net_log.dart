import 'dart:async';

import 'net_record.dart';

/// 环形缓冲，保留最近 [capacity] 条。
///
/// WebView 一个页面能发几千个请求，无上限缓冲会吃光内存。
class NetLog {
  NetLog({this.capacity = 200});

  final int capacity;
  final _records = <NetRecord>[];
  final _controller = StreamController<void>.broadcast();

  /// 最新的在前。
  List<NetRecord> get records => List.unmodifiable(_records.reversed);

  Stream<void> get changes => _controller.stream;

  void add(NetRecord record) {
    _records.add(record);
    if (_records.length > capacity) _records.removeAt(0);
    if (!_controller.isClosed) _controller.add(null);
  }

  void clear() {
    _records.clear();
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}
