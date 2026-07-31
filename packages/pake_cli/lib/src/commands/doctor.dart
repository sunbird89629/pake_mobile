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
