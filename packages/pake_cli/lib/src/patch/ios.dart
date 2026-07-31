import 'package:pake_config/pake_config.dart';

import 'url.dart';

const _permsBegin = '\t<!-- pake:permissions:begin -->';
const _permsEnd = '\t<!-- pake:permissions:end -->';

const _atsBegin = '\t<!-- pake:ats:begin -->';
const _atsEnd = '\t<!-- pake:ats:end -->';

/// 把 app 名、传输安全例外与权限用途说明写进 `ios/Runner/Info.plist`。
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

  final permissions = [
    _permsBegin,
    for (final p in config.permissions) ...[
      '\t<key>${p.iosUsageKey}</key>',
      '\t<string>${_escapeXmlText(p.iosUsageDescription)}</string>',
    ],
    _permsEnd,
  ].join('\n');

  // ATS 默认禁明文 HTTP，跟 Android 的 usesCleartextTraffic 是一回事：
  // 不开这个例外，`pakem build http://192.168.1.10:8080` 构建成功、装上白屏。
  //
  // 用 NSAllowsArbitraryLoads 而不是按域名开 NSExceptionDomains：设置页可以
  // 在运行期把 URL 改到另一个 http 地址，按构建期域名开例外会让那条路径
  // 又白屏一次——而这正是这个壳存在的意义。它只在用户显式用 http 构建时
  // 才写进去。
  //
  // 权限块必须先插：ATS 块自带一层 <dict>，先插它会让下面的 lastIndexOf
  // 定位到 ATS 内层的 </dict>，权限键就被塞进嵌套字典里，iOS 直接忽略。
  final ats = [
    _atsBegin,
    if (isCleartextUrl(config.url)) ...[
      '\t<key>NSAppTransportSecurity</key>',
      '\t<dict>',
      '\t\t<key>NSAllowsArbitraryLoads</key>',
      '\t\t<true/>',
      '\t</dict>',
    ],
    _atsEnd,
  ].join('\n');

  out = _upsertBlock(
    out,
    begin: _permsBegin,
    end: _permsEnd,
    block: permissions,
  );
  return _upsertBlock(out, begin: _atsBegin, end: _atsEnd, block: ats);
}

/// 标记块已存在就整块替换，否则插到**根**字典的闭合标签前。
///
/// 根字典的 `</dict>` 紧跟在 `</plist>` 前，所以用 lastIndexOf 定位它。
/// 用 replaceFirst 会错误地命中嵌套字典（如 UIApplicationSceneManifest 内
/// 的），键被 iOS 忽略并在设备上崩溃。
String _upsertBlock(
  String plist, {
  required String begin,
  required String end,
  required String block,
}) {
  final existing = RegExp(
    '${RegExp.escape(begin)}.*?${RegExp.escape(end)}',
    dotAll: true,
  );
  if (existing.hasMatch(plist)) return plist.replaceFirst(existing, block);

  final rootClose = plist.lastIndexOf('</dict>');
  return '${plist.substring(0, rootClose)}$block\n${plist.substring(rootClose)}';
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
