import 'package:flutter/material.dart';

enum LoadFailureKind { offline, badUrl, serverError }

/// 分类决定给用户什么建议。给断网的人一个「改 URL」按钮是误导。
///
/// `errorType` 传的是 `WebResourceErrorType.toValue()`——真实包里没有一个
/// 简单 Dart enum 挂 `.name`，这些字面量必须跟包里 `WebResourceErrorType`
/// 的实际取值对齐（见 flutter_inappwebview_platform_interface 的
/// `web_resource_error_type.dart`）。
LoadFailureKind classifyFailure({int? httpStatus, String? errorType}) {
  if (httpStatus != null) {
    return httpStatus >= 500
        ? LoadFailureKind.serverError
        : LoadFailureKind.badUrl;
  }

  return switch (errorType?.toUpperCase()) {
    'HOST_LOOKUP' ||
    'CANNOT_CONNECT_TO_HOST' ||
    'NOT_CONNECTED_TO_INTERNET' ||
    'NETWORK_CONNECTION_LOST' ||
    'IO' ||
    'TIMEOUT' => LoadFailureKind.offline,
    'BAD_URL' || 'UNSUPPORTED_SCHEME' => LoadFailureKind.badUrl,
    _ => LoadFailureKind.serverError,
  };
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.kind,
    required this.url,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LoadFailureKind kind;
  final String url;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  String get _message => switch (kind) {
    LoadFailureKind.offline =>
      'No network connection. Check your Wi-Fi or mobile data, then retry.',
    LoadFailureKind.badUrl =>
      'Could not load $url. The address may be wrong — open settings to change it.',
    LoadFailureKind.serverError =>
      'The server at $url returned an error. It may be temporarily down.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kind == LoadFailureKind.offline
                      ? Icons.wifi_off
                      : Icons.error_outline,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(_message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                const SizedBox(height: 8),
                // EscapeHatch 是兜底通道，但有明确错误页时应给明确按钮。
                TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
