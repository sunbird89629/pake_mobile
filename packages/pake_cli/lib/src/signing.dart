import 'dart:io';

import 'package:path/path.dart' as p;

import 'output.dart';
import 'process_runner.dart';

class SigningIdentity {
  const SigningIdentity(this.name);
  final String name;
}

final _identityPattern = RegExp(
  r'^\s+\d+\)\s+\S+\s+"(.+)"\s*$',
  multiLine: true,
);

List<SigningIdentity> parseIdentities(String securityOutput) => _identityPattern
    .allMatches(securityOutput)
    .map((m) => SigningIdentity(m[1]!))
    .toList();

class ProvisioningProfile {
  const ProvisioningProfile({
    required this.name,
    required this.expiry,
    required this.appId,
  });

  final String name;
  final DateTime expiry;

  /// 形如 `TEAMID.com.example.app`，或通配 `TEAMID.*`。
  final String appId;

  bool get isExpired => expiry.isBefore(DateTime.now());

  bool matches(String bundleId) {
    final withoutTeam = appId.contains('.')
        ? appId.substring(appId.indexOf('.') + 1)
        : appId;
    if (withoutTeam == '*') return true;
    if (withoutTeam.endsWith('.*')) {
      return bundleId.startsWith(
        withoutTeam.substring(0, withoutTeam.length - 1),
      );
    }
    return withoutTeam == bundleId;
  }
}

/// 在 build 之前把签名问题挡下来，不等 xcodebuild 输出。
Future<void> checkIosSigning({
  required ProcessRunner runner,
  required String profileName,
  required String bundleId,
  required List<ProvisioningProfile> profiles,
}) async {
  final result = await runner.run('security', [
    'find-identity',
    '-v',
    '-p',
    'codesigning',
  ]);
  if (parseIdentities(result.stdout.toString()).isEmpty) {
    throw PakeException(
      ExitCodes.environment,
      'No codesigning identity found. Open Xcode → Settings → Accounts and '
      'add your Apple ID, or import a signing certificate.',
    );
  }

  final profile = profiles.where((p) => p.name == profileName).firstOrNull;
  if (profile == null) {
    final available = profiles.map((p) => p.name).join(', ');
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" not found. '
      'Available: ${available.isEmpty ? '(none)' : available}',
    );
  }

  if (profile.isExpired) {
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" expired on '
      '${profile.expiry.toIso8601String().split('T').first}. '
      'Regenerate it in Xcode or on the Apple Developer portal.',
    );
  }

  if (!profile.matches(bundleId)) {
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" is for ${profile.appId}, '
      'which does not cover bundle id "$bundleId".',
    );
  }
}

/// 扫 `~/Library/MobileDevice/Provisioning Profiles/`。
///
/// `.mobileprovision` 是 CMS 签名过的 plist，用 `security cms -D -i` 解出
/// 明文再抓两个字段——比引 plist 解析库轻。
Future<List<ProvisioningProfile>> loadInstalledProfiles(
  ProcessRunner runner, {
  String? home,
}) async {
  final dir = Directory(
    p.join(
      home ?? Platform.environment['HOME'] ?? '',
      'Library/MobileDevice/Provisioning Profiles',
    ),
  );
  if (!dir.existsSync()) return const [];

  final profiles = <ProvisioningProfile>[];
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.mobileprovision')) continue;

    final decoded = await runner.run('security', [
      'cms',
      '-D',
      '-i',
      file.path,
    ]);
    final xml = decoded.stdout.toString();

    final name = _plistString(xml, 'Name');
    final appId = _plistString(xml, 'application-identifier');
    final expiry = _plistDate(xml, 'ExpirationDate');
    if (name == null || appId == null || expiry == null) continue;

    profiles.add(ProvisioningProfile(name: name, expiry: expiry, appId: appId));
  }
  return profiles;
}

String? _plistString(String xml, String key) => RegExp(
  '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
).firstMatch(xml)?[1];

DateTime? _plistDate(String xml, String key) {
  final raw = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<date>([^<]*)</date>',
  ).firstMatch(xml)?[1];
  return raw == null ? null : DateTime.tryParse(raw);
}
