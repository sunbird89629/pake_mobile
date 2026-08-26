import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pake_cli/src/icon_discovery.dart';
import 'package:test/test.dart';

const baseUri = 'https://example.com/page';

/// 按 path 应答的假 client，没登记的一律 404。
///
/// 三个碰网络的函数（[parseManifestIcons] / [tryFaviconIco] /
/// [discoverIconUrls]）签名里都留了 `http.Client?`——那个注入口就是为可测
/// 才加的，但测试一直没写。这里补上。
/// `Uri.parse('https://example.com').path` 是空串而不是 `/`——真实服务器
/// 把两者当同一个资源，这里也归一化，免得路由表要为它写两个键。
MockClient _client(Map<String, http.Response> routes) =>
    MockClient((request) async {
      final path = request.url.path.isEmpty ? '/' : request.url.path;
      return routes[path] ?? _notFound;
    });

final _notFound = http.Response('', 404);

/// 一个只挂了 [links] 的页面。
String _page(String links) => '<html><head>$links</head></html>';

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

  group('parseManifestIcons', () {
    test('collects icons and resolves src against the manifest url', () async {
      // src 要按 **manifest 自己的** URL 解析，不是页面的：清单常放在
      // /static/ 之类的子目录下，按页面解析会把路径拼到站点根上去。
      final candidates = await parseManifestIcons(
        Uri.parse('https://example.com/page'),
        '/static/site.webmanifest',
        client: _client({
          '/static/site.webmanifest': http.Response(
            '{"icons":[{"src":"icon-512.png","sizes":"512x512"}]}',
            200,
          ),
        }),
      );

      expect(candidates.single.url, 'https://example.com/static/icon-512.png');
      expect(candidates.single.tier, IconTier.manifestIcon);
    });

    // 清单是别人服务器上的东西，什么形状都可能。任何一种畸形都只意味着
    // 「这一步没收获」，继续走 D/E，不该冒泡打断整个发现流程。
    test('returns empty for anything malformed instead of throwing', () async {
      Future<List<IconCandidate>> parse(http.Response response) =>
          parseManifestIcons(
            Uri.parse(baseUri),
            '/m.json',
            client: _client({'/m.json': response}),
          );

      expect(await parse(http.Response('{}', 404)), isEmpty);
      expect(await parse(http.Response('not json at all', 200)), isEmpty);
      expect(await parse(http.Response('[1,2,3]', 200)), isEmpty);
      expect(await parse(http.Response('{"icons":"nope"}', 200)), isEmpty);
      expect(await parse(http.Response('{"icons":[{}]}', 200)), isEmpty);
    });
  });

  group('tryFaviconIco', () {
    test('is a candidate only when HEAD says 200', () async {
      final found = await tryFaviconIco(
        Uri.parse(baseUri),
        client: _client({'/favicon.ico': http.Response('', 200)}),
      );
      expect(found!.url, 'https://example.com/favicon.ico');
      expect(found.tier, IconTier.faviconIco);

      expect(
        await tryFaviconIco(Uri.parse(baseUri), client: _client({})),
        isNull,
      );
    });

    // favicon.ico 永远挂在站点根上。页面 URL 带路径/查询串/锚点时若不清干净，
    // 拼出来的会是 /page?x=1#y 那种打不开的地址。
    test(
      'anchors at the site root, dropping path, query and fragment',
      () async {
        final found = await tryFaviconIco(
          Uri.parse('https://example.com/deep/page?x=1#frag'),
          client: _client({'/favicon.ico': http.Response('', 200)}),
        );

        expect(found!.url, 'https://example.com/favicon.ico');
      },
    );
  });

  group('discoverIconUrls', () {
    // build.dart 的循环直接遍历这个返回值，空列表意味着连试都不试。
    // Google favicon 是无条件追加的保底项，所以永远至少有它。
    test('never comes back empty, even when the site offers nothing', () async {
      final urls = await discoverIconUrls(
        'https://example.com',
        client: _client({}),
      );

      expect(urls.single, contains('google.com/s2/favicons'));
    });

    // B/C 那层 catch 兜的就是这个：网页本身抓不到时，D/E 仍要走完。
    test('still reaches favicon.ico when the page fetch throws', () async {
      final urls = await discoverIconUrls(
        'https://example.com',
        client: MockClient((request) async {
          if (request.url.path == '/favicon.ico') {
            return http.Response('', 200);
          }
          throw Exception('network is down');
        }),
      );

      expect(urls, contains('https://example.com/favicon.ico'));
    });

    // GitHub 那个 512×512 正是从 manifest 来的——修好 SVG 排序后能拿到图标，
    // 靠的就是这条路径。
    test('merges manifest icons into the queue', () async {
      final urls = await discoverIconUrls(
        'https://example.com',
        client: _client({
          '/': http.Response(
            _page('<link rel="manifest" href="/app.webmanifest">'),
            200,
          ),
          '/app.webmanifest': http.Response(
            '{"icons":[{"src":"/icon-512.png","sizes":"512x512"}]}',
            200,
          ),
        }),
      );

      expect(urls.first, 'https://example.com/icon-512.png');
    });

    // 垫底不是丢掉：只挂 SVG 的站点仍然要能试一次，日志才说得清
    // 「试过了、解不了」。
    test('keeps SVG in the queue but behind everything else', () async {
      final urls = await discoverIconUrls(
        'https://example.com',
        client: _client({
          '/': http.Response(
            _page(
              '<link rel="icon" type="image/svg+xml" href="/icon.svg">'
              '<link rel="apple-touch-icon" sizes="180x180" href="/apple.png">',
            ),
            200,
          ),
        }),
      );

      expect(urls.first, 'https://example.com/apple.png');
      expect(urls.last, 'https://example.com/icon.svg');
    });
  });
}
