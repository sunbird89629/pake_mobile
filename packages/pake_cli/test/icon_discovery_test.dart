import 'package:pake_cli/src/icon_discovery.dart';
import 'package:test/test.dart';

const baseUri = 'https://example.com/page';

void main() {
  group('parseLinkIcons', () {
    // SVG 曾经排在最前（矢量、缩放无损），但 `package:image` 解不了它——
    // GitHub 这类只挂 SVG favicon 的站点因此必然拿不到图标，回落默认。
    // 现在它垫底：能解码的格式优先，SVG 只在别无选择时才轮到。
    test('ranks SVG below every decodable format', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/apple.png'));

      // 但它仍然是候选队列的一员，只是排在最后。
      expect(rankedUrls(candidates).last, endsWith('/icon.svg'));
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

      // 认得出它是 SVG——这正是把它排到最后所依赖的判断。
      final svg = candidates.firstWhere((c) => c.url.endsWith('/icon.svg'));
      expect(svg.tier, IconTier.svg);

      // 认出来的后果是让位，不是优先。
      expect(bestOf(candidates)!.url, endsWith('/huge.png'));
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
      // regular icon (tier 2, 16px) = -2000 + 16 = -1984
      // shortcut icon (tier 3, 256px) = -3000 + 256 = -2744
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

      // multi: 48px → -2000 + 48 = -1952
      // single: 64px → -2000 + 64 = -1936  ← higher
      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/single.png'));
    });

    // `sizes="any"` 给 999 的维度加成，但加成只在同 tier 内起作用——
    // tier 之间差 1000 分，999 跨不过去。SVG 垫底之后这个加成再也翻不了盘，
    // 留着它是为了让多个 SVG 之间仍有个排序。
    test('the "any" dimension bonus cannot lift SVG over another tier', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
</head></html>
''');

      final best = bestOf(candidates)!;
      expect(best.url, endsWith('/apple.png'));
    });
  });

  // 只返回「最佳」的那一个是不够的：评分是猜的，而猜错没有第二次机会。
  // 后缀会骗人（x.com 的 apple-touch-icon.png 返回 287KB 首页 HTML），
  // 格式也未必解得了。调用方要拿到整条队列，一个个试到能用为止。
  group('rankedUrls', () {
    test('orders every candidate best-first, not just the winner', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="shortcut icon" sizes="256x256" href="/shortcut.png">
<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
<link rel="icon" sizes="512x512" href="/huge.png">
</head></html>
''');

      expect(rankedUrls(candidates), [
        'https://example.com/apple.png', // appleTouch
        'https://example.com/huge.png', // iconLarge
        'https://example.com/shortcut.png', // shortcutIcon
        'https://example.com/icon.svg', // svg，垫底
      ]);
    });

    test('drops duplicate urls so the same fetch is not retried', () {
      final candidates = parseLinkIcons(Uri.parse(baseUri), '''
<html><head>
<link rel="apple-touch-icon" sizes="180x180" href="/same.png">
<link rel="icon" sizes="32x32" href="/same.png">
</head></html>
''');

      expect(rankedUrls(candidates), ['https://example.com/same.png']);
    });

    test('is empty for no candidates', () {
      expect(rankedUrls(const []), isEmpty);
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
