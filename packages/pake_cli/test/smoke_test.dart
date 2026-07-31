@Tags(['smoke'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// 真实构建一次 release APK，断言产物存在。
///
/// `runBuild` 总是传 `--release`（见 build_pipeline.dart），没有 debug 产物。
///
/// 本地跑太慢（Android 冷构建数分钟），所以打 `smoke` tag，
/// 默认排除，只在 CI 跑：`dart test --tags smoke`。
void main() {
  test(
    'pakem build produces an apk and json output',
    () async {
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
