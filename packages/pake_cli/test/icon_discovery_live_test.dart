@Tags(['smoke'])
library;

import 'package:pake_cli/src/commands/icon.dart';
import 'package:pake_cli/src/icon_discovery.dart';
import 'package:test/test.dart';

/// 真打真网络的图标发现验证。默认跳过，显式跑：
///
/// ```bash
/// dart test test/icon_discovery_live_test.dart --run-skipped
/// ```
///
/// 与 `icon_discovery_test.dart` 的分工：那边喂假 HTML 和 `MockClient`，
/// 锁的是解析和排序逻辑；这边打真站点，答的是另一个问题——**真实世界的
/// 网页到底长什么样**。前者永远不会告诉你 x.com 的 apple-touch-icon 返回
/// 的是 287KB 首页 HTML，那种事只有真连上去才知道。
///
/// x.com 是三种失效方式凑齐的活标本，图标发现的三个 bug 都是它暴露的：
///
/// - `apple-touch-icon.png` 返回 200 + 首页 HTML —— 后缀骗人
/// - `favicon.ico` 能解码，但只有 32×32 —— 不够用
/// - 真正能用的 512×512 排在第三位 —— 只赌第一个就拿不到
void main() {
  // 断言刻意宽松：不锁死具体 URL，也不锁死它排第几。站点随时改版，而这个
  // 测试要守住的是「x.com 能被 pakem 拿到一张够大的图标」，不是「今天它
  // 长什么样」——后者写下来就是在给自己埋一个必然会红的定时炸弹。
  test('x.com yields a usable icon somewhere in its queue', () async {
    const site = 'https://www.x.com';

    final urls = await discoverIconUrls(site);
    print('候选队列（$site）:');
    for (final url in urls) {
      print('  $url');
    }

    expect(urls, isNotEmpty, reason: 'Google favicon 是无条件保底项，至少该有它');

    // 3 和 192 对应 build.dart 里的 _maxIconAttempts / _goodEnoughIconSize
    // ——那两个是私有的，这里重复一遍数字，为的是让这个测试回答的问题和
    // 真实构建完全一致：**按 build 的规则走，这个站点拿得到图标吗**。
    int? best;
    String? bestUrl;
    for (final url in urls.take(3)) {
      final size = await _sizeOf(url);
      print('  → ${size ?? "解不开"}  ${Uri.parse(url).pathSegments.lastOrNull}');
      if (size != null && (best == null || size > best)) {
        best = size;
        bestUrl = url;
      }
      if (best != null && best >= 192) break;
    }

    expect(best, isNotNull, reason: '前三个候选一个都解不开，构建会回落到默认图标');
    expect(
      best,
      greaterThanOrEqualTo(192),
      reason:
          '最大只有 ${best}px（$bestUrl），拉到 xxxhdpi 的 192 会糊。'
          '要么排序需要调整，要么这个站点确实没有够大的图标',
    );
  });
}

/// 下载并解码，拿不到就返回 null。网络错误在这里等同于「这个候选不可用」
/// ——`build` 那边也是这么处理的。
Future<int?> _sizeOf(String url) async {
  try {
    return decodedIconSize(await fetchIconBytes(url));
  } catch (_) {
    return null;
  }
}
