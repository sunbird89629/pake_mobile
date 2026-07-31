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
    return parts.join(' ');
  }
}

/// 单引号内的单引号必须写成 `'\''`，否则拼出来的命令不合法。
String _shellEscape(String value) => value.replaceAll("'", r"'\''");
