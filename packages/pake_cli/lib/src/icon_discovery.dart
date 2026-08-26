import 'dart:convert';

import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

/// 图标发现顺序，从高到低优先。
///
/// `score` 用 `-(tier.order * 1000) + clampedDimension`，同 tier 内按
/// 尺寸排序。调用方只需要 `best.score`——这个 enum 起文档作用。
enum IconTier {
  /// `<link rel="apple-touch-icon">`，通常 180×180 起。不加尺寸说明
  /// 也至少是 60×60，比 16×16 favicon 强。
  appleTouch(0),

  /// `<link rel="icon">` 带显式 sizes ≥144px。
  iconLarge(1),

  /// `<link rel="icon">` 带显式 sizes <144px。
  iconSmall(2),

  /// `<link rel="shortcut icon">`。
  shortcutIcon(3),

  /// PWA `manifest.json` 里 `icons[]` 中的条目。
  manifestIcon(4),

  /// `/favicon.ico`。
  faviconIco(5),

  /// Google S2 favicon 服务：`google.com/s2/favicons?domain=X&sz=256`。
  googleFavicon(6),

  /// SVG：矢量、缩放无损——**但 `package:image` 解不了它**，拿到了也只能
  /// 丢掉回落默认图标。这一层原本排在最前（`sizes="any"` 还额外加 999 分），
  /// 结果是 GitHub 这类用 SVG favicon 的站点**必然**拿不到图标。
  ///
  /// 排到最末而不是直接删掉：真有站点只提供 SVG 时，它仍然是唯一候选，
  /// 留着至少能让日志说清「试过了、解不了」。
  svg(7);

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

/// 按 A→B→C→D→E 优先级链发现图标候选，按评分从高到低返回**全部**。
///
/// 返回列表而不是单个「最佳」：评分只是猜测，而下载回来才知道那东西到底
/// 能不能用。调用方逐个试到解得开为止——见 [rankedUrls]。
///
/// 调用方负责 A（用户显式 `--icon`）——在外部跳过。
Future<List<String>> discoverIconUrls(
  String siteUrl, {
  http.Client? client,
}) async {
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

    return rankedUrls(candidates);
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

/// 全部候选按评分从高到低，去重。
///
/// 只返回最优的那一个是不够的：评分是**猜**的，而猜错没有第二次机会。
/// 后缀会骗人（`x.com/apple-touch-icon.png` 返回的是 287KB 首页 HTML），
/// 格式也未必解得了。调用方拿到整条队列，可以一个个试到能用为止。
List<String> rankedUrls(List<IconCandidate> candidates) {
  final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));

  final seen = <String>{};
  return [
    for (final c in sorted)
      if (seen.add(c.url)) c.url,
  ];
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
