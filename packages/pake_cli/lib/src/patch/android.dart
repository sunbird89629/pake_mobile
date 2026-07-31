import 'package:pake_config/pake_config.dart';

import 'url.dart';

const _permsBegin = '    <!-- pake:permissions:begin -->';
const _permsEnd = '    <!-- pake:permissions:end -->';

/// 把 CLI 管的字段写进 `android/app/build.gradle.kts`。
///
/// minSdk / targetSdk 保持 flutter 默认——那是 Flutter 工具链的事，
/// pake 不该越界。
String patchBuildGradle(String original, PakeConfig config) {
  return original
      .replaceAll(
        RegExp(r'namespace\s*=\s*"[^"]*"'),
        'namespace = "${config.bundleId}"',
      )
      .replaceAll(
        RegExp(r'applicationId\s*=\s*"[^"]*"'),
        'applicationId = "${config.bundleId}"',
      )
      .replaceAll(
        RegExp(r'versionCode\s*=\s*[^\n]+'),
        'versionCode = ${config.buildNumber}',
      )
      .replaceAll(
        RegExp(r'versionName\s*=\s*[^\n]+'),
        'versionName = "${config.version}"',
      );
}

/// 把 app 名、明文 HTTP 开关与权限声明写进
/// `android/app/src/main/AndroidManifest.xml`。
String patchAndroidManifest(String original, PakeConfig config) {
  var out = original.replaceAll(
    RegExp(r'android:label="[^"]*"'),
    'android:label="${_escapeXmlAttribute(config.name)}"',
  );

  // Android 9+ 默认禁明文 HTTP。构建期 URL 是 http 却不开这个开关，装上就是
  // 永远白屏——而且失败会落进 classifyFailure 的默认分支，告诉用户「服务器
  // 返回了错误」，指错方向。对着局域网 dev server 打包正是本工具最常见的
  // 用法，不是边角情况。
  //
  // 先无条件删掉旧属性再按需加回：固定 workspace 会被复用，上一个 app 是
  // http、这一个是 https 时，不删就会把明文开关带进来。
  out = out.replaceAll(RegExp(r'\s+android:usesCleartextTraffic="[^"]*"'), '');
  if (isCleartextUrl(config.url)) {
    out = out.replaceFirst(
      '<application',
      '<application android:usesCleartextTraffic="true"',
    );
  }

  // INTERNET is never optional for a webview shell — always include it as the
  // first permission. Then add declared permissions, filtering out INTERNET
  // to avoid duplicates.
  final permissions = <String>[
    '    <uses-permission android:name="android.permission.INTERNET"/>',
  ];
  for (final p in config.permissions) {
    if (p.androidPermission != 'android.permission.INTERNET') {
      permissions.add(
        '    <uses-permission android:name="${p.androidPermission}"/>',
      );
    }
  }

  final block = [_permsBegin, ...permissions, _permsEnd].join('\n');

  final existing = RegExp(
    '${RegExp.escape(_permsBegin)}.*?${RegExp.escape(_permsEnd)}',
    dotAll: true,
  );

  if (existing.hasMatch(out)) {
    return out.replaceFirst(existing, block);
  }

  // 首次 patch：插在 </manifest> 之前。
  return out.replaceFirst('</manifest>', '$block\n</manifest>');
}

String _escapeXmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
