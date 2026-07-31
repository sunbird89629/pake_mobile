import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/signing.dart';
import 'package:test/test.dart';

class _FakeRunner implements ProcessRunner {
  // ignore: unused_element_parameter
  _FakeRunner(this.stdout, {this.exitCode = 0});
  final String stdout;
  final int exitCode;

  @override
  Future<ProcessResult> run(
    String e,
    List<String> a, {
    String? workingDirectory,
  }) async => ProcessResult(0, exitCode, stdout, '');
}

void main() {
  group('parseIdentities', () {
    test('extracts identity names from security output', () {
      const output = '''
  1) A1B2C3 "Apple Development: Hao Wang (ABC123)"
  2) D4E5F6 "Apple Distribution: Hao Wang (ABC123)"
     2 valid identities found
''';

      final ids = parseIdentities(output);

      expect(ids.map((i) => i.name), [
        'Apple Development: Hao Wang (ABC123)',
        'Apple Distribution: Hao Wang (ABC123)',
      ]);
    });

    test('returns empty when no identities are found', () {
      expect(parseIdentities('     0 valid identities found\n'), isEmpty);
    });
  });

  group('ProvisioningProfile', () {
    test('is expired when the expiry date is in the past', () {
      final p = ProvisioningProfile(
        name: 'Old',
        expiry: DateTime.now().subtract(const Duration(days: 1)),
        appId: 'ABCDE.com.pake.weibo',
      );
      expect(p.isExpired, isTrue);
    });

    test('is not expired when the expiry date is in the future', () {
      final p = ProvisioningProfile(
        name: 'Fresh',
        expiry: DateTime.now().add(const Duration(days: 30)),
        appId: 'ABCDE.com.pake.weibo',
      );
      expect(p.isExpired, isFalse);
    });
  });

  group('checkIosSigning', () {
    final fresh = ProvisioningProfile(
      name: 'Pake Dev',
      expiry: DateTime.now().add(const Duration(days: 30)),
      appId: 'ABCDE.com.pake.weibo',
    );

    test('passes when a valid identity and matching profile exist', () async {
      await checkIosSigning(
        runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
        profileName: 'Pake Dev',
        bundleId: 'com.pake.weibo',
        profiles: [fresh],
      );
    });

    test('fails with exit code 2 when there is no codesigning identity', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('     0 valid identities found\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.weibo',
          profiles: [fresh],
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.environment,
          ),
        ),
      );
    });

    test('fails when the named profile is missing', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Nonexistent',
          bundleId: 'com.pake.weibo',
          profiles: [fresh],
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.message,
            'message',
            contains('Nonexistent'),
          ),
        ),
      );
    });

    test('fails with an explicit message when the profile has expired', () {
      final expired = ProvisioningProfile(
        name: 'Pake Dev',
        expiry: DateTime.now().subtract(const Duration(days: 2)),
        appId: 'ABCDE.com.pake.weibo',
      );

      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.weibo',
          profiles: [expired],
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('fails when the profile app id does not match the bundle id', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.other',
          profiles: [fresh],
        ),
        throwsA(
          isA<PakeException>().having(
            (e) => e.message,
            'message',
            contains('com.pake.other'),
          ),
        ),
      );
    });

    test('accepts a wildcard profile app id', () async {
      final wildcard = ProvisioningProfile(
        name: 'Wildcard',
        expiry: DateTime.now().add(const Duration(days: 30)),
        appId: 'ABCDE.*',
      );

      await checkIosSigning(
        runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
        profileName: 'Wildcard',
        bundleId: 'com.pake.anything',
        profiles: [wildcard],
      );
    });
  });

  group('androidSigningMode', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('pake-signing'));
    tearDown(() => home.deleteSync(recursive: true));

    void writeProps(String content) {
      Directory('${home.path}/.pake').createSync(recursive: true);
      File('${home.path}/.pake/signing.properties').writeAsStringSync(content);
    }

    test('reports debug when no signing.properties exists', () {
      expect(androidSigningMode(home: home.path), 'debug');
    });

    test('reports release when storeFile is set', () {
      writeProps('''
storeFile=/keys/pake-release.jks
storePassword=secret
keyAlias=pake
keyPassword=secret
''');
      expect(androidSigningMode(home: home.path), 'release');
    });

    test('treats a blank storeFile as unconfigured, like gradle does', () {
      writeProps('storeFile=\nkeyAlias=pake\n');
      expect(androidSigningMode(home: home.path), 'debug');
    });

    test('ignores a commented-out storeFile', () {
      writeProps('# storeFile=/keys/old.jks\nkeyAlias=pake\n');
      expect(androidSigningMode(home: home.path), 'debug');
    });

    // 两个键名都是 `storeFile` 的近邻，各挡一类错误实现：
    // `storeFilePassword` 挡 startsWith/contains，`mystoreFile` 挡
    // endsWith/contains。少任何一个，对应的错误实现都能蒙混过关。
    test('does not match keys that merely contain storeFile', () {
      writeProps('storeFilePassword=secret\nmystoreFile=/keys/old.jks\n');
      expect(androidSigningMode(home: home.path), 'debug');
    });
  });
}
