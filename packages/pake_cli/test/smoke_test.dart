@Tags(['smoke'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// 真实构建一次 debug APK，断言产物存在。
///
/// 本地跑太慢（Android 冷构建数分钟），所以打 `smoke` tag，
/// 默认排除，只在 CI 跑：`dart test --tags smoke`。
void main() {
  test(
    'pakem build produces an apk and json output',
    () async {
      final tmp = Directory.systemTemp.createTempSync('pakem_smoke');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final result = await Process.run('dart', [
        'run',
        'bin/pakem.dart',
        'build',
        'https://example.com',
        '--name',
        'Smoke',
        '--bundle-id',
        'com.pake.smoke',
        '--platform',
        'android',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());

      final json = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(json['ok'], isTrue);

      final artifacts = json['artifacts']! as List;
      expect(artifacts, isNotEmpty);
      expect(File(artifacts.first! as String).existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
