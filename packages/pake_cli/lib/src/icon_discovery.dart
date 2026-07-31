import 'dart:convert';

import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

/// 图标发现顺序，从高到低优先。
///
/// `score` 用 `-(tier.order * 1000) + clampedDimension`，同 tier 内按
/// 尺寸排序。调用方只需要 `best.score`——这个 enum 起文档作用。
enum IconTier {
  /// SVG：矢量，缩放无损。匹配 `type="image/svg+xml"` 和 URL 以 `.svg`
  /// 结尾的 `rel="icon"`。
  svg(0),

  /// `<link rel="apple-touch-icon">`，通常 180×180 起。不加尺寸说明
  /// 也至少是 60×60，比 16×16 favicon 强。
  appleTouch(1),

  /// `<link rel="icon">` 带显式 sizes ≥144px。
  iconLarge(2),

  /// `<link rel="icon">` 带显式 sizes <144px。
  iconSmall(3),

  /// `<link rel="shortcut icon">`。
  shortcutIcon(4),

  /// PWA `manifest.json` 里 `icons[]` 中的条目。
  manifestIcon(5),

  /// `/favicon.ico`。
  faviconIco(6),

  /// Google S2 favicon 服务：`google.com/s2/favicons?domain=X&sz=256`。
  googleFavicon(7);

  const IconTier(this.order);
  final int order;
}

class IconCandidate {
  const IconCandidate({
    required this.url,
    required this.score,
    required this.tier,
  });

  /// 绝对值越小越优先。
  /// 公式: `score = -(tier.order * 1000) + min(maxDimension, 999)`。
  final int score;

  final String url;
  final IconTier tier;
}

// ===========================================================================
// 解析 HTML <link> 图标
// ===========================================================================

/// 从页面 HTML 里提取 `<link rel="…">` 图标候选。
List<IconCandidate> parseLinkIcons(Uri pageUri, String html) {
  final document = parser.parse(html);
  final candidates = <IconCandidate>[];

  for (final link in document.querySelectorAll('link[rel]')) {
    final rel = (link.attributes['rel'] ?? '').toLowerCase();
    final href = link.attributes['href'];
    if (href == null || href.isEmpty) continue;

    final url = _resolve(pageUri, href);
    final type = (link.attributes['type'] ?? '').toLowerCase();
    final sizes = link.attributes['sizes'] ?? '';

    if (rel == 'icon' || rel == 'shortcut icon') {
      final tier = rel == 'shortcut icon'
          ? IconTier.shortcutIcon
          : IconTier.iconLarge;

      if (type == 'image/svg+xml' || url.path.endsWith('.svg')) {
        candidates.add(_candidate(url, IconTier.svg, sizes));
        continue;
      }

      if (type.isNotEmpty && !type.startsWith('image/')) continue;

      candidates.add(_candidate(url, tier, sizes));
    }

    if (rel == 'apple-touch-icon' || rel == 'apple-touch-icon-precomposed') {
      candidates.add(_candidate(url, IconTier.appleTouch, sizes));
    }
  }

  return candidates;
}

// ===========================================================================
// 解析 manifest.json
// ===========================================================================

/// 从 `manifest.json` 里提取图标候选。
/// 失败返回空列表，调用方继续往下走。
Future<List<IconCandidate>> parseManifestIcons(
  Uri pageUri,
  String manifestUrl, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final uri = _resolve(pageUri, manifestUrl);
    final response = await c.get(uri);
    if (response.statusCode != 200) return [];

    Object? json;
    try {
      json = jsonDecode(response.body) as Object?;
    } catch (_) {
      return [];
    }
    if (json is! Map<String, Object?>) return [];

    final icons = json['icons'];
    if (icons is! List) return [];

    final candidates = <IconCandidate>[];
    for (final entry in icons.whereType<Map<String, Object?>>()) {
      final src = entry['src'] as String?;
      if (src == null || src.isEmpty) continue;
      final sizes = entry['sizes'] as String? ?? '';

      candidates.add(
        _candidate(_resolve(uri, src), IconTier.manifestIcon, sizes),
      );
    }
    return candidates;
  } finally {
    if (client == null) c.close();
  }
}

// ===========================================================================
// 兜底策略
// ===========================================================================

/// HEAD `/favicon.ico`，200 才返回候选。不验证图片内容——下游 fetch 时做。
Future<IconCandidate?> tryFaviconIco(Uri pageUri, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final url = pageUri.replace(
      path: '/favicon.ico',
      query: null,
      fragment: null,
    );
    final response = await c.head(url);
    if (response.statusCode != 200) return null;

    return _candidate(url, IconTier.faviconIco, '');
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Google S2 favicon 服务。
IconCandidate googleFaviconFor(String domain) => _candidate(
  Uri.parse('https://www.google.com/s2/favicons?domain=$domain&sz=256'),
  IconTier.googleFavicon,
  '256x256',
);

// ===========================================================================
// 主入口
// ===========================================================================

/// 按 A→B→C→D→E 优先级链发现图标 URL，返回评分最高的，或 null。
///
/// 调用方负责 A（用户显式 `--icon`）——在外部跳过。
Future<String?> discoverIconUrl(String siteUrl, {http.Client? client}) async {
  final c = client ?? http.Client();
  final pageUri = Uri.parse(siteUrl);

  try {
    var candidates = <IconCandidate>[];

    // B + C: 页面 <link> 和 manifest.json
    try {
      final response = await c.get(pageUri);
      if (response.statusCode == 200) {
        candidates.addAll(parseLinkIcons(pageUri, response.body));

        final document = parser.parse(response.body);
        final manifestLink = document.querySelector('link[rel="manifest"]');
        final manifestHref = manifestLink?.attributes['href'];
        if (manifestHref != null && manifestHref.isNotEmpty) {
          candidates.addAll(
            await parseManifestIcons(pageUri, manifestHref, client: c),
          );
        }
      }
    } catch (_) {
      // 网页抓不到就跳过 B/C，继续 D/E。
    }

    // D: /favicon.ico
    final favicon = await tryFaviconIco(pageUri, client: c);
    if (favicon != null) candidates.add(favicon);

    // E: Google favicon（永远作为保底）
    candidates.add(googleFaviconFor(pageUri.host));

    return bestOf(candidates)?.url;
  } finally {
    if (client == null) c.close();
  }
}

/// 评分最高的候选，或 null。
IconCandidate? bestOf(List<IconCandidate> candidates) {
  if (candidates.isEmpty) return null;
  var best = candidates.first;
  for (final c in candidates.skip(1)) {
    if (c.score > best.score) best = c;
  }
  return best;
}

// ===========================================================================
// 内部工具
// ===========================================================================

IconCandidate _candidate(Uri url, IconTier tier, String sizes) =>
    IconCandidate(url: url.toString(), score: _score(tier, sizes), tier: tier);

/// `score = -(tier.order * 1000) + clampedDimension`。
/// SVG（`sizes="any"`）维度给 999，在一切非 SVG 之上。
int _score(IconTier tier, String sizes) {
  final dims = _maxDimension(sizes);
  return -(tier.order * 1000) + dims.clamp(0, 999);
}

/// `"16x16 32x32 48x48"` → 48，`"any"` → 999，空 → 0。
int _maxDimension(String sizes) {
  if (sizes.isEmpty) return 0;
  if (sizes.trim().toLowerCase() == 'any') return 999;

  var max = 0;
  for (final part in sizes.split(RegExp(r'\s+'))) {
    final n = int.tryParse(part.split('x').first);
    if (n != null && n > max) max = n;
  }
  return max;
}

Uri _resolve(Uri base, String href) => base.resolve(href);
