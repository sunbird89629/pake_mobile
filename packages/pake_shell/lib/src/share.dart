import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// 分享当前页时发出去的正文。
///
/// 标题和 URL 拼成两行，而不是只发 URL。Android 上标题本该走
/// `EXTRA_SUBJECT`（Chrome 就是这么发的），但真正去读它的接收方很少——
/// 微信、QQ 这类只取 `EXTRA_TEXT`，只发 URL 的话对面收到一条光秃秃的链接，
/// 看不出是哪部片。`subject` 照样带上，读它的那些 app 白赚。
///
/// 标题为空、或标题本身就是这个 URL（站点不给 `<title>` 时 WebView 会把地址
/// 当标题返回）时只发 URL——同一行重复一遍没有信息量。
String shareTextFor({required String url, String? title}) {
  final trimmed = title?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == url) return url;
  return '$trimmed\n$url';
}

/// 调系统分享面板。
///
/// [origin] 是 iPad 上那个 popover 的锚点矩形，手机上给不给都一样。
Future<void> sharePage({
  required String url,
  String? title,
  Rect? origin,
}) async {
  final subject = title?.trim() ?? '';
  await SharePlus.instance.share(
    ShareParams(
      text: shareTextFor(url: url, title: title),
      subject: subject.isEmpty ? null : subject,
      sharePositionOrigin: origin,
    ),
  );
}
