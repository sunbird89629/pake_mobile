enum NetSource {
  /// 来自注入的 fetch/XHR hook——有 body。
  js,

  /// 来自 onLoadResource——只有 URL 与时序。
  resource,
}

class NetRecord {
  const NetRecord({
    required this.url,
    required this.method,
    required this.status,
    required this.durationMs,
    required this.at,
    this.body,
    this.requestBody,
    this.requestHeaders = const {},
    this.source = NetSource.js,
  });

  /// 解析 net_hook.js 经 callHandler 回传的对象。
  ///
  /// 一律防御性取值：页面里的脚本能改 `window.fetch` 的参数形状，
  /// 一个畸形 payload 不该让请求面板崩掉。
  factory NetRecord.fromHandlerJson(Map<Object?, Object?> json) => NetRecord(
    url: json['url'] is String ? json['url']! as String : '(unknown)',
    method: json['method'] is String ? json['method']! as String : 'GET',
    status: json['status'] is int ? json['status']! as int : -1,
    durationMs: json['ms'] is int ? json['ms']! as int : 0,
    at: DateTime.now(),
    body: json['body'] is String ? json['body']! as String : null,
  );

  final String url;
  final String method;

  /// `-1` 表示请求失败或状态未知。
  final int status;
  final int durationMs;
  final DateTime at;
  final String? body;
  final String? requestBody;
  final Map<String, String> requestHeaders;
  final NetSource source;

  String toCurl() {
    final parts = <String>["curl -X $method '${_shellEscape(url)}'"];
    for (final entry in requestHeaders.entries) {
      parts.add("-H '${_shellEscape('${entry.key}: ${entry.value}')}'");
    }
    final rb = requestBody;
    if (rb != null && rb.isNotEmpty) {
      parts.add("--data-raw '${_shellEscape(rb)}'");
    }
    // net_hook.js 从来不抓请求头/体（范围有意排除的）——不加这句，导出的
    // 命令看着像一次忠实回放，其实一个请求头都没有。
    var curl = parts.join(' ');
    // 换行加注释：macOS 默认交互式 zsh 没开 INTERACTIVE_COMMENTS，同一行
    // 里的 `#` 不会被当注释，curl 会把后面的词当成额外的 URL 报错。
    if (requestHeaders.isEmpty && (rb == null || rb.isEmpty)) {
      curl = '$curl\n# note: request headers/body were not captured';
    }
    return curl;
  }
}

/// 单引号内的单引号必须写成 `'\''`，否则拼出来的命令不合法。
String _shellEscape(String value) => value.replaceAll("'", r"'\''");
