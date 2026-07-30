import 'package:pake_config/pake_config.dart';

const _permsBegin = '\t<!-- pake:permissions:begin -->';
const _permsEnd = '\t<!-- pake:permissions:end -->';

/// 把 app 名与权限用途说明写进 `ios/Runner/Info.plist`。
///
/// 版本号**不动**——它由 `flutter build --build-name/--build-number` 经
/// `$(FLUTTER_BUILD_NAME)` 变量注入，直接改 plist 会和工具链打架。
String patchInfoPlist(String original, PakeConfig config) {
  // 必须用 replaceFirstMapped：Dart 的 replaceFirst 把 replacement 当字面量，
  // 不解析 $1 / ${1} 这类反向引用（那是 JS 的语义）。
  var out = original.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*\n\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}${_escapeXmlText(config.name)}${m[2]}',
  );

  final block = [
    _permsBegin,
    for (final p in config.permissions) ...[
      '\t<key>${p.iosUsageKey}</key>',
      '\t<string>${_escapeXmlText(p.iosUsageDescription)}</string>',
    ],
    _permsEnd,
  ].join('\n');

  final existing = RegExp(
    '${RegExp.escape(_permsBegin)}.*?${RegExp.escape(_permsEnd)}',
    dotAll: true,
  );

  if (existing.hasMatch(out)) {
    return out.replaceFirst(existing, block);
  }

  return out.replaceFirst('</dict>', '$block\n</dict>');
}

/// 改 `ios/Runner.xcodeproj/project.pbxproj` 里的 bundle id。
///
/// 用 `replaceAllMapped` 保留 `.RunnerTests` 这类后缀——直接整行替换会
/// 把 test target 的 id 也压成主 target 的，导致签名冲突。
String patchPbxproj(String original, PakeConfig config) {
  return original.replaceAllMapped(
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+?)(\.RunnerTests)?;'),
    (m) => 'PRODUCT_BUNDLE_IDENTIFIER = ${config.bundleId}${m[2] ?? ''};',
  );
}

/// 生成 `flutter build ipa --export-options-plist` 要的文件。
String exportOptionsPlist({
  required String teamId,
  required String profileName,
  required String bundleId,
  String method = 'development',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>$method</string>
	<key>teamID</key>
	<string>$teamId</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>provisioningProfiles</key>
	<dict>
		<key>$bundleId</key>
		<string>$profileName</string>
	</dict>
</dict>
</plist>
''';
}

String _escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
