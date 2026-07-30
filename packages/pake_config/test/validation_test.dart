import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

PakeConfig _valid({
  String name = 'Demo',
  String url = 'https://example.com',
  String bundleId = 'com.example.demo',
  String version = '1.0.0',
  String? iconPath,
  List<String> injectScripts = const [],
}) =>
    PakeConfig(
      name: name,
      url: url,
      bundleId: bundleId,
      version: version,
      iconPath: iconPath,
      injectScripts: injectScripts,
    );

/// 除显式列出的路径外都不存在。
bool Function(String) _fsWith(Set<String> present) => present.contains;

void main() {
  group('validateConfig', () {
    test('accepts a fully valid config', () {
      expect(validateConfig(_valid(), fileExists: _fsWith({})), isEmpty);
    });

    test('rejects a blank name', () {
      final errors = validateConfig(_valid(name: '  '), fileExists: _fsWith({}));
      expect(errors.map((e) => e.field), contains('name'));
    });

    test('rejects non-http schemes', () {
      for (final bad in ['ftp://example.com', 'file:///tmp/a.html', 'nonsense']) {
        final errors = validateConfig(_valid(url: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('url'), reason: bad);
      }
    });

    test('rejects a url without a host', () {
      final errors =
          validateConfig(_valid(url: 'https://'), fileExists: _fsWith({}));
      expect(errors.map((e) => e.field), contains('url'));
    });

    test('rejects malformed bundle ids', () {
      for (final bad in ['nodots', 'com..example', '1com.example', 'com.exa mple', 'com.example-app']) {
        final errors =
            validateConfig(_valid(bundleId: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('bundleId'), reason: bad);
      }
    });

    test('accepts bundle ids with underscores and digits after the first char', () {
      for (final ok in ['com.example.app2', 'com.my_org.demo_app']) {
        final errors =
            validateConfig(_valid(bundleId: ok), fileExists: _fsWith({}));
        expect(errors, isEmpty, reason: ok);
      }
    });

    test('rejects a version that is not x.y.z', () {
      for (final bad in ['1.0', 'v1.0.0', '1.0.0-beta']) {
        final errors =
            validateConfig(_valid(version: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('version'), reason: bad);
      }
    });

    test('rejects a missing icon file', () {
      final errors = validateConfig(
        _valid(iconPath: 'missing.png'),
        fileExists: _fsWith({}),
      );
      expect(errors.map((e) => e.field), contains('iconPath'));
    });

    test('accepts an icon file that exists', () {
      final errors = validateConfig(
        _valid(iconPath: 'icon.png'),
        fileExists: _fsWith({'icon.png'}),
      );
      expect(errors, isEmpty);
    });

    test('reports each unreadable inject script separately', () {
      final errors = validateConfig(
        _valid(injectScripts: ['there.js', 'gone.js', 'alsogone.css']),
        fileExists: _fsWith({'there.js'}),
      );
      expect(errors.length, 2);
      expect(errors.every((e) => e.field == 'injectScripts'), isTrue);
      expect(errors.map((e) => e.message).join(), contains('gone.js'));
    });

    test('reports every problem at once rather than stopping at the first', () {
      final errors = validateConfig(
        _valid(name: '', url: 'nonsense', bundleId: 'bad'),
        fileExists: _fsWith({}),
      );
      expect(errors.map((e) => e.field), containsAll(['name', 'url', 'bundleId']));
    });
  });
}
