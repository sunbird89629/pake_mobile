import 'dart:io';

import 'package:args/command_runner.dart';

import '../output.dart';
import '../process_runner.dart';
import '../signing.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._output, {ProcessRunner? runner})
    : _runner = runner ?? const RealProcessRunner();

  final Output _output;
  final ProcessRunner _runner;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check the build environment and signing setup.';

  @override
  Future<int> run() async {
    final checks = <String, Object?>{};

    final flutter = await _runner.run('flutter', ['--version']);
    checks['flutter'] = flutter.exitCode == 0
        ? flutter.stdout.toString().split('\n').first
        : 'NOT FOUND';

    // `pakem release` 全靠它跟 GitHub 说话，鉴权也在它手里。缺了不影响构建，
    // 所以不参与退出码判定。
    final gh = await _runner.run('gh', ['--version']);
    checks['gh'] = gh.exitCode == 0
        ? gh.stdout.toString().split('\n').first
        : 'NOT FOUND (needed by `pakem release`)';

    if (Platform.isMacOS) {
      final identities = parseIdentities(
        (await _runner.run('security', [
          'find-identity',
          '-v',
          '-p',
          'codesigning',
        ])).stdout.toString(),
      );
      checks['codesigningIdentities'] = [for (final i in identities) i.name];

      final profiles = await loadInstalledProfiles(_runner);
      checks['provisioningProfiles'] = [
        for (final p in profiles)
          '${p.name} → ${p.appId}'
              '${p.isExpired ? ' (EXPIRED ${p.expiry.toIso8601String().split('T').first})' : ''}',
      ];
    } else {
      checks['ios'] = 'skipped (not macOS)';
    }

    _output.success(checks);
    return checks['flutter'] == 'NOT FOUND' ? ExitCodes.environment : 0;
  }
}
