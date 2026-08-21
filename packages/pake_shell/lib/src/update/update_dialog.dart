import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_check.dart';

/// 跳系统浏览器，把下载和安装都交给系统。
///
/// 不在 app 内下载 APK：那要 `REQUEST_INSTALL_PACKAGES` 权限、FileProvider
/// 配置、下载进度与断点，而 iOS 分支照样只能跳链接——两套代码换一个一年
/// 用几次的功能，不值。
Future<bool> openDownload(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// 每个新版号只弹一次：点「稍后」写 `dismissedUpdateVersion`，下一版照弹。
///
/// 返回值仅供测试与调用方记录，UI 上无差别。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  required void Function(String version) onDismiss,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Update available: ${info.version}'),
    content: info.notes.isEmpty
        ? null
        : ConstrainedBox(
            // release notes 是远端文本，长度不可控；不限高会把按钮顶出屏幕。
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(child: Text(info.notes)),
          ),
    actions: [
      TextButton(
        onPressed: () {
          onDismiss(info.version);
          Navigator.of(context).pop();
        },
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.of(context).pop();
          openDownload(info.downloadUrl);
        },
        child: const Text('Update'),
      ),
    ],
  ),
);
