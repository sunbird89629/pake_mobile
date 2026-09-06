import 'package:flutter/material.dart';

/// 「更多」菜单里的一条。取消返回 `null`。
enum MoreAction { shareApp, goHome, copyCurrentUrl, openInExternalBrowser }

/// 从底部栏的 ⋯ 弹出「更多」。
///
/// 用底部弹层而不是锚在按钮上的下拉菜单：入口本来就贴着屏幕底边，弹层正好
/// 出现在拇指底下，而 `showMenu` 的浮层会往屏幕中间飘。
///
/// 之所以是一个菜单而不是直接在栏上再加一个按钮：栏是钉死宽度的四个
/// 触控格，往栏里塞第五个按钮在窄屏上就装不下了。回主页、复制当前 URL、
/// 用外部浏览器打开这些排队的都进这里，菜单把按钮数封顶在四个。
Future<MoreAction?> showMoreMenu(BuildContext context) {
  return showModalBottomSheet<MoreAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('more:share-app'),
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share app'),
            onTap: () => Navigator.of(context).pop(MoreAction.shareApp),
          ),
          ListTile(
            key: const ValueKey('more:go-home'),
            leading: const Icon(Icons.home_outlined),
            title: const Text('Home'),
            onTap: () => Navigator.of(context).pop(MoreAction.goHome),
          ),
          ListTile(
            key: const ValueKey('more:copy-url'),
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy URL'),
            onTap: () => Navigator.of(context).pop(MoreAction.copyCurrentUrl),
          ),
          ListTile(
            key: const ValueKey('more:open-in-browser'),
            leading: const Icon(Icons.open_in_browser_outlined),
            title: const Text('Open in browser'),
            onTap: () =>
                Navigator.of(context).pop(MoreAction.openInExternalBrowser),
          ),
        ],
      ),
    ),
  );
}
