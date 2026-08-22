import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  group('versionCodeFor', () {
    // 系统只认 versionCode，认不出 versionName——它不跟着 version 走的话，
    // bump 完版本号两个包在系统眼里一模一样。
    test('is monotonic in the version it came from', () {
      const ordered = ['1.0.0', '1.0.1', '1.0.99', '1.1.0', '1.99.99', '2.0.0'];

      final codes = ordered.map(versionCodeFor).toList();

      expect(codes, [10000, 10001, 10099, 10100, 19999, 20000]);
      expect(codes, orderedEquals(List.of(codes)..sort()));
    });

    // versionCode 必须是正数，而 validateConfig 已经把非法 version 拦在前面。
    test('falls back to 1 rather than emitting 0 or throwing', () {
      for (final bad in ['', '1.0', '1.2.3.4', 'x.y.z', '1.-2.0', '0.0.0']) {
        expect(versionCodeFor(bad), 1, reason: bad);
      }
    });
  });

  group('PakeConfig', () {
    test('serialization round-trips all fields', () {
      const original = PakeConfig(
        name: 'Demo',
        url: 'https://example.com',
        bundleId: 'com.example.demo',
        version: '1.2.3',
        buildNumber: 7,
        iconPath: 'assets/icon.png',
        injectScripts: ['a.js', 'b.css'],
        permissions: [PakePermission.camera, PakePermission.location],
      );

      final restored = PakeConfig.fromJson(original.toJson());

      expect(restored, equals(original));
    });

    // 同一个 version 要重发一次包时的后门。
    test('an explicit buildNumber overrides the derived versionCode', () {
      const c = PakeConfig(
        name: 'Demo',
        url: 'https://example.com',
        bundleId: 'com.example.demo',
        version: '1.2.3',
        buildNumber: 7,
      );

      expect(versionCodeFor(c.version), 10203);
      expect(c.versionCode, 7);
    });

    test('fromJson applies defaults for omitted optional fields', () {
      final c = PakeConfig.fromJson({
        'name': 'Minimal',
        'url': 'https://example.com',
        'bundleId': 'com.example.minimal',
      });

      expect(c.version, '1.0.0');
      expect(c.buildNumber, isNull);
      expect(c.versionCode, 10000);
      expect(c.iconPath, isNull);
      expect(c.injectScripts, isEmpty);
      expect(c.permissions, isEmpty);
    });

    test('copyWith replaces only the named field', () {
      const c = PakeConfig(
        name: 'Demo',
        url: 'https://example.com',
        bundleId: 'com.example.demo',
      );

      expect(c.copyWith(url: 'https://other.com').url, 'https://other.com');
      expect(c.copyWith(url: 'https://other.com').name, 'Demo');
    });

    test('permission maps to platform-specific identifiers', () {
      expect(
        PakePermission.camera.androidPermission,
        'android.permission.CAMERA',
      );
      expect(PakePermission.camera.iosUsageKey, 'NSCameraUsageDescription');
    });
  });
}
