import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// 分享 app 时发出去的正文。
///
/// 第一行 app 名，第二行功能介绍（构建期配置里的 `description`，没有就
/// 跳过），最后一行下载地址。介绍比链接重要：影视站这类 app 靠口口相传，
/// 朋友点开链接之前先要知道「这是什么、能干什么」。
///
/// 曾经分享的是当前页（标题 + 站点 URL），那是错的——朋友拿着站点地址
/// 装不了壳，只有 app 的 release 页才装得下「推荐这个 app」这件事。
String shareTextFor({
  required String name,
  String? description,
  required String url,
}) {
  final lines = [name];
  final trimmed = description?.trim() ?? '';
  if (trimmed.isNotEmpty) lines.add(trimmed);
  lines.add(url);
  return lines.join('\n');
}

/// 调系统分享面板，分享 app 本身：名 + 介绍 + 本版本 release 页地址。
///
/// [origin] 是 iPad 上那个 popover 的锚点矩形，手机上给不给都一样。
Future<void> shareApp({
  required String name,
  String? description,
  required String url,
  Rect? origin,
}) async {
  // subject 走 EXTRA_SUBJECT，Android 上真正读它的接收方很少（微信、QQ 只取
  // EXTRA_TEXT），但读的那些 app 白赚一个标题，带上无成本。
  await SharePlus.instance.share(
    ShareParams(
      text: shareTextFor(name: name, description: description, url: url),
      subject: name,
      sharePositionOrigin: origin,
    ),
  );
}
