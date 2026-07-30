import 'package:pake_cli/src/patch/scripts.dart';
import 'package:test/test.dart';

void main() {
  group('materializeScript', () {
    test('derives a stable id from the file name', () {
      final s = materializeScript(
        path: 'scripts/remove-ads.js',
        content: 'console.log(1);',
      );

      expect(s.id, 'remove-ads');
      expect(s.kind, ScriptKind.js);
    });

    test('wraps js in a try/catch so one bad script cannot kill the page', () {
      final s = materializeScript(
        path: 'a.js',
        content: 'throw new Error("boom");',
      );

      expect(s.source, contains('try {'));
      expect(s.source, contains('throw new Error("boom");'));
      expect(s.source, contains('catch'));
      expect(
        s.source,
        contains('console.error'),
        reason: 'errors must reach onConsoleMessage to land in the log',
      );
      expect(
        s.source,
        contains('[pake:a]'),
        reason: 'the log line must name the offending script',
      );
    });

    test('turns css into a style-injecting script', () {
      final s = materializeScript(
        path: 'theme.css',
        content: 'body { background: red; }',
      );

      expect(s.kind, ScriptKind.css);
      expect(s.source, contains('createElement'));
      expect(s.source, contains('body { background: red; }'));
      expect(s.source, contains('try {'));
    });

    test(
      'escapes backticks and \${ so css cannot break out of the template',
      () {
        final s = materializeScript(
          path: 'evil.css',
          content: r'body::after { content: "`${alert(1)}`"; }',
        );

        expect(s.source, contains(r'\`'));
        expect(s.source, contains(r'\${'));
      },
    );

    test('rejects an unsupported extension', () {
      expect(
        () => materializeScript(path: 'thing.txt', content: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('id survives a path with directories and dots', () {
      final s = materializeScript(
        path: '/tmp/my.stuff/fix-video.min.js',
        content: '',
      );

      expect(s.id, 'fix-video.min');
    });
  });
}
