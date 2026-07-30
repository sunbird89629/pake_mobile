import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
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

    test('fromJson applies defaults for omitted optional fields', () {
      final c = PakeConfig.fromJson({
        'name': 'Minimal',
        'url': 'https://example.com',
        'bundleId': 'com.example.minimal',
      });

      expect(c.version, '1.0.0');
      expect(c.buildNumber, 1);
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
