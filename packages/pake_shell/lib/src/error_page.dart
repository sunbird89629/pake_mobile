import 'package:flutter/material.dart';

import 'debug_ui.dart';

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

/// `onReceivedError`/`onReceivedHttpError` fire for *every* resource a page
/// loads — images, XHR, fonts, analytics — not just the main document. Only
/// a main-frame failure should cover the screen with [ErrorPage]; a failing
/// sub-resource is diagnostic noise, and the working page underneath it
/// must stay visible.
///
/// `isForMainFrame` is nullable in the plugin's type. Both platforms this
/// app targets populate it in practice: Android's `WebResourceRequest`
/// always carries a primitive (non-null) `isForMainFrame`, and on iOS it is
/// hardcoded `true` for `onReceivedError` (WKWebView's `didFail` delegate
/// method only ever fires for main-frame navigation failures — there is no
/// callback for sub-resource load errors) and set from
/// `WKNavigationResponse.isForMainFrame` for `onReceivedHttpError`. So
/// `null` should not occur here. If it ever does, we treat it as "not main
/// frame" (don't surface an error page) rather than "main frame" — this
/// matches the plugin's own precedent for its deprecated single-argument
/// callbacks (`request.isForMainFrame ?? false`), and it fails toward the
/// bug we are fixing (a hidden sub-resource failure — the page stays up, so
/// the bottom bar stays up with it and settings is still one tap away)
/// rather than back into it (an innocuous sub-resource error blanking out a
/// working page).
bool shouldSurfaceError({required bool? isForMainFrame}) =>
    isForMainFrame ?? false;

class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.kind,
    required this.url,
    required this.onRetry,
    required this.onOpenSettings,
    this.canEditUrl = kShowDebugSettings,
  });

  final LoadFailureKind kind;
  final String url;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  /// 设置页里还有没有那个能改 URL 的输入框。正式包里没有（见
  /// [kShowDebugSettings]），那句「open settings to change it」就成了把人
  /// 支去一个不存在的地方。
  final bool canEditUrl;

  String get _message => switch (kind) {
    LoadFailureKind.offline =>
      'No network connection. Check your Wi-Fi or mobile data, then retry.',
    LoadFailureKind.badUrl when canEditUrl =>
      'Could not load $url. The address may be wrong — open settings to change it.',
    LoadFailureKind.badUrl =>
      'Could not load $url. The address may be wrong, or the site may have moved.',
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
                // 错误页把整棵 WebView 子树换掉了，底部胶囊连同上面的 ⚙
                // 一起不在树里——这个按钮是错误页上唯一的设置入口，不能省。
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
