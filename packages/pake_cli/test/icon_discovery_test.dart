import 'package:pake_cli/src/icon_discovery.dart';
import 'package:test/test.dart';

const baseUri = 'https://example.com/page';

void main() {
  group('parseLinkIcons', () {
    test('prefers SVG over any PNG regardless of size', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/icon.svg'));
      expect(best.tier, IconTier.svg);
    });

    test('apple-touch-icon beats any non-SVG icon', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="apple-touch-icon" sizes="60x60" href="/apple.png">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/apple.png'));
      expect(best.tier, IconTier.appleTouch);
    });

    test('larger icon wins within same tier', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" sizes="32x32" href="/small.png">
<link rel="icon" sizes="192x192" href="/large.png">
<link rel="icon" sizes="48x48" href="/medium.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/large.png'));
    });

    test('recognises .svg extension even without explicit type', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" href="/icon.svg" sizes="32x32">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/icon.svg'));
      expect(best.tier, IconTier.svg);
    });

    test('resolves relative URLs against page URI', () {
      final candidates = parseLinkIcons(
        Uri.parse('https://example.com/blog/index.html'),
        '<html><head><link rel="icon" href="../icon.png"></head></html>',
      );

      expect(candidates.single.url, 'https://example.com/icon.png');
    });

    test('skips non-image type attribute', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="application/xml" href="/feed.xml">
<link rel="icon" sizes="48x48" href="/favicon.png">
</head></html>
''');

      expect(candidates.length, 1);
      expect(candidates.single.url, endsWith('/favicon.png'));
    });

    test('shortcut icon has lower priority than regular icon', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="shortcut icon" sizes="256x256" href="/shortcut.png">
<link rel="icon" sizes="16x16" href="/icon.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      // regular icon (tier 3, 16px) = -3000 + 16 = -2984
      // shortcut icon (tier 4, 256px) = -4000 + 256 = -3744
      // regular icon wins despite smaller size
      expect(best.url, endsWith('/icon.png'));
    });

    test(
      'apple-touch-icon-precomposed is treated same as apple-touch-icon',
      () {
        final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="apple-touch-icon-precomposed" sizes="180x180" href="/precomposed.png">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

        final best = bestOf(candidates)!;
        expect(best.url, endsWith('/precomposed.png'));
        expect(best.tier, IconTier.appleTouch);
      },
    );
  });

  group('score ranking', () {
    test('multi-size attribute picks the largest', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" sizes="16x16 32x32 48x48" href="/multi.png">
<link rel="icon" sizes="64x64" href="/single.png">
</head></html>
''');

      // multi: 48px → -3000 + 48 = -2952
      // single: 64px → -3000 + 64 = -2936  ← higher
      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/single.png'));
    });

    test('sizes="any" (SVG) beats all fixed dimensions', () {
      // This needs an SVG type to get the svg tier — "any" alone doesn't
      // auto-promote.
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/icon.svg'));
    });
  });

  group('googleFaviconFor', () {
    test('generates the correct URL', () {
      final candidate = googleFaviconFor('example.com');
      expect(
        candidate.url,
        'https://www.google.com/s2/favicons?domain=example.com&sz=256',
      );
    });
  });
}
