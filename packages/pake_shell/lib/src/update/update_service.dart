import 'dart:convert';
import 'dart:io';

import '../runtime_config.dart';
import 'update_check.dart';

/// 取远端 JSON 的那一层。真实实现是 HttpClient，测试传假的——纯逻辑那边
/// 收的是已经取回来的字符串，网络只在这一层出现。
typedef Fetcher = Future<String> Function(Uri uri);

/// 自动检查的节流窗口。网页壳被系统杀掉后重启很频繁，不节流就是一天几十次
/// 请求（GitHub 未登录限流 60/小时/IP）。
const updateCheckInterval = Duration(hours: 24);

/// 有副作用的那一层：网络、时钟、存储。纯逻辑全在 [update_check.dart]。
class UpdateService {
  UpdateService(this.config, {Fetcher? fetch, DateTime Function()? now})
    : _fetch = fetch ?? _httpFetch,
      _now = now ?? DateTime.now;

  final RuntimeConfig config;
  final Fetcher _fetch;
  final DateTime Function() _now;

  /// 冷启动路径：开关关着、还在节流窗口内、或者任何一步失败，都返回 null，
  /// **一个提示都不弹**。
  ///
  /// `api.github.com` 在墙内经常不可达，而 4kvm 这类预设的用户恰恰在墙内
  /// ——「查不到更新」在这里是常态而非异常，任何形式的报错都是噪音。
  Future<UpdateInfo?> checkOnLaunch() async {
    if (!config.updateCheckEnabled) return null;

    final last = config.lastUpdateCheckAt;
    if (last != null && _now().difference(last) < updateCheckInterval) {
      return null;
    }

    final UpdateInfo? info;
    try {
      info = await check();
    } catch (_) {
      // 超时、DNS 污染、403 限流、JSON 变形——全都只意味着「这次没查到」。
      // 时间戳也不记：断网启动一次就把接下来 24 小时全吞掉，等于用户一整天
      // 连上网也查不到。
      return null;
    }

    config.lastUpdateCheckAt = _now();
    if (info == null) return null;
    return info.version == config.dismissedUpdateVersion ? null : info;
  }

  /// 手动路径：无视开关和节流，异常原样抛给调用方去显示。
  ///
  /// 这是唯一能拿到「已是最新版」这个确定答复的地方，被节流掉就没意义了。
  Future<UpdateInfo?> check() async {
    final body = await _fetch(releasesEndpoint());

    return pickUpdate(
      body: body,
      bundleId: config.buildTime.bundleId,
      currentVersion: config.buildTime.version,
    );
  }
}

/// `dart:io` 够用了，不为一次 GET 引 `package:http`。
Future<String> _httpFetch(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    // GitHub 要求带 User-Agent，不带会被 403。
    request.headers.set(HttpHeaders.userAgentHeader, 'pake_mobile');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );

    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}
