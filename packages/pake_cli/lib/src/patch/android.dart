import 'package:pake_config/pake_config.dart';

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

/// 把 app 名与权限声明写进 `android/app/src/main/AndroidManifest.xml`。
String patchAndroidManifest(String original, PakeConfig config) {
  var out = original.replaceAll(
    RegExp(r'android:label="[^"]*"'),
    'android:label="${_escapeXmlAttribute(config.name)}"',
  );

  final block = [
    _permsBegin,
    for (final p in config.permissions)
      '    <uses-permission android:name="${p.androidPermission}"/>',
    _permsEnd,
  ].join('\n');

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
