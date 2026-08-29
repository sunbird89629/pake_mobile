import 'package:flutter/material.dart';

/// 「更多」菜单里的一条。取消返回 `null`。
enum MoreAction { share }

/// 从底部栏的 ⋯ 弹出「更多」。
///
/// 用底部弹层而不是锚在按钮上的下拉菜单：入口本来就贴着屏幕底边，弹层正好
/// 出现在拇指底下，而 `showMenu` 的浮层会往屏幕中间飘。
///
/// 之所以是一个菜单而不是直接在栏上再加一个分享按钮：栏是钉死宽度的几个
/// 触控格，roadmap 上排队等这个位置的还有「复制当前 URL」和「用外部浏览器
/// 打开」，都往栏里塞按钮就塞不下了。菜单把按钮数封顶在四个。
Future<MoreAction?> showMoreMenu(BuildContext context) {
  return showModalBottomSheet<MoreAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('more:share'),
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            onTap: () => Navigator.of(context).pop(MoreAction.share),
          ),
        ],
      ),
    ),
  );
}
