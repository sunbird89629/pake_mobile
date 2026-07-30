import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  group('mergeConfig', () {
    test('flags override same-named fields in the file', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'FromFile',
          'url': 'https://file.example.com',
          'bundleId': 'com.example.fromfile',
        },
        flags: const PakeFlags(url: 'https://flag.example.com'),
      );

      expect(merged.url, 'https://flag.example.com');
      expect(
        merged.name,
        'FromFile',
        reason: 'unspecified flags must not clobber',
      );
      expect(merged.bundleId, 'com.example.fromfile');
    });

    test('works with flags only when no file is present', () {
      final merged = mergeConfig(
        flags: const PakeFlags(
          name: 'FlagsOnly',
          url: 'https://example.com',
          bundleId: 'com.example.flagsonly',
        ),
      );

      expect(merged.name, 'FlagsOnly');
      expect(merged.version, '1.0.0', reason: 'falls back to model default');
    });

    test('works with a file only when no flags are given', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'FileOnly',
          'url': 'https://example.com',
          'bundleId': 'com.example.fileonly',
          'version': '2.0.0',
        },
      );

      expect(merged.name, 'FileOnly');
      expect(merged.version, '2.0.0');
    });

    test('an empty --inject list still overrides the file list', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'D',
          'url': 'https://example.com',
          'bundleId': 'com.example.d',
          'injectScripts': ['from-file.js'],
        },
        flags: const PakeFlags(injectScripts: []),
      );

      expect(merged.injectScripts, isEmpty);
    });

    test('produces an empty config when given neither source', () {
      final merged = mergeConfig();
      expect(merged.name, isEmpty);
      expect(merged.url, isEmpty);
    });
  });

  group('RuntimeKeys', () {
    test(
      'keys are namespaced so they cannot collide with debug_sheet history',
      () {
        // debug_sheet 用 md5(title) 当 key（32 位十六进制），
        // 加前缀即可保证永不相撞。
        for (final k in [
          RuntimeKeys.url,
          RuntimeKeys.userAgent,
          RuntimeKeys.enabledScripts,
          RuntimeKeys.logLevel,
          RuntimeKeys.fullscreen,
        ]) {
          expect(k, startsWith('pake.'));
        }
      },
    );
  });

  group('UserAgentPresets', () {
    test('exposes the four presets named in the design', () {
      expect(
        UserAgentPresets.all.keys,
        containsAll(['iOS Safari', 'Android Chrome', 'Desktop', 'Default']),
      );
    });
  });
}
