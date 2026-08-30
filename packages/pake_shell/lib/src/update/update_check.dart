import 'dart:convert';

/// 所有 app 的 release 都挂在主仓，靠 tag 前缀区分。
const updateRepo = 'sunbird89629/pake_mobile';

/// 只拉一页。`per_page=100` 是 GitHub 允许的上限，不是「够用」的推算——
/// 主仓里所有 app 的 release 共享这个列表（按创建时间倒序），某个 app 的
/// 最新版一旦被别的 app 挤出这 100 条，它的用户就**永远收不到更新且毫无
/// 征兆**。以当前发版频率能撑很多年，真撑不住时要加分页。
Uri releasesEndpoint([String repo = updateRepo]) =>
    Uri.parse('https://api.github.com/repos/$repo/releases?per_page=100');

/// 一个可供升级的版本。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.downloadUrl,
    this.notes = '',
  });

  final String version;
  final String tag;

  /// 优先是 `.apk` 直链，没有 apk 时回落到 release 页面。
  final String downloadUrl;
  final String notes;
}

/// tag 前缀取 bundleId 末段：`com.pake.fourkvm` → `fourkvm`。
///
/// 用 bundleId 而不是 app 名：bundleId 本来就不能改（改了就是另一个 app），
/// 而 app 名可能是中文或带空格，还随时会被改掉——那会静默断掉所有已装用户
/// 的更新链路。
String tagPrefixFor(String bundleId) => bundleId.split('.').last;

/// 三段比较。`a > b` 返回正数，相等返回 0。
///
/// 段数不齐时短的一方补 0（`1.2` == `1.2.0`）。非数字段当 0——解析不出来的
/// 版本号一律不该触发升级，交给调用方连同 [parseVersion] 的 null 一起挡掉。
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final diff = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (diff != 0) return diff;
  }
  return 0;
}

/// `1.2.0` → `[1, 2, 0]`，解析不出来返回 null。
///
/// 猜是危险的：一个解析不出的版本号当「没新版」处理，最坏是漏一次提示；
/// 当「有新版」处理则可能把所有人推到一个不存在的包上。
List<int>? parseVersion(String version) {
  final parts = version.split('.');
  if (parts.isEmpty || parts.length > 3) return null;

  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    numbers.add(value);
  }
  return numbers;
}

/// `fourkvm-v1.2.0` + 前缀 `fourkvm` → `[1, 2, 0]`。前缀不匹配返回 null，
/// 这正是「主仓里属于别的 app 的 release」被滤掉的地方。
List<int>? parseTag(String tag, String prefix) {
  final expected = '$prefix-v';
  if (!tag.startsWith(expected)) return null;
  return parseVersion(tag.substring(expected.length));
}

/// 本 app 某个版本的 release 页面地址，分享 app 时发出去。
///
/// tag 格式沿用 [parseTag] 承认的 `<bundleId 末段>-v<version>`——CLI 的
/// `tagFor()` 是写的一方，壳是读的一方，格式的真相源在 CLI，改格式要两边
/// 一起改。这里拼的是 [parseTag] 那个规则，所以两边对得上。
///
/// 指向 release 页而不是 APK 直链：一条 release 挂三个 ABI 的包，直链只能
/// 钉死一个（通常是 arm64），发到别的设备上就是「应用未安装」。release 页
/// 让人按设备自己挑。
Uri releasePageUrl({
  required String bundleId,
  required String version,
  String repo = updateRepo,
}) => Uri.parse(
  'https://github.com/$repo/releases/tag/${tagPrefixFor(bundleId)}-v$version',
);

/// 从 `/releases` 的响应里挑出比 [currentVersion] 更新的那个。
///
/// 结构不对、字段缺失、一个都不匹配，全都返回 null——这条路径上任何异常都
/// 只意味着「这次没查到」，不该冒泡。
UpdateInfo? pickUpdate({
  required String body,
  required String appName,
  required String bundleId,
  required String currentVersion,
}) {
  final prefix = tagPrefixFor(bundleId);
  final current = parseVersion(currentVersion);
  if (current == null) return null;

  final List<Object?> releases;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return null;
    releases = decoded;
  } on FormatException {
    return null;
  }

  UpdateInfo? best;
  List<int>? bestVersion;

  for (final entry in releases) {
    if (entry is! Map<String, Object?>) continue;

    // draft 未登录本来就看不到，过滤它纯属防御；prerelease 才是有意义的那个
    // ——发一个 prerelease 自己先装上验，验完取消勾选才推给所有人。
    if (entry['draft'] == true || entry['prerelease'] == true) continue;

    final tag = entry['tag_name'];
    if (tag is! String) continue;

    final version = parseTag(tag, prefix);
    if (version == null) continue;
    if (compareVersions(version, current) <= 0) continue;

    // 列表是按创建时间倒序的，不是按版本。给旧版本补发一次 release（补个
    // 说明、换个 asset）就会让它排到最前面——取第一个会把所有人「升级」
    // 到更旧的包。
    if (bestVersion != null && compareVersions(version, bestVersion) <= 0) {
      continue;
    }

    final url = _downloadUrl(entry, appName);
    // 连 html_url 都没有的 release 点了也没地方去，当它不存在。
    if (url.isEmpty) continue;

    bestVersion = version;
    best = UpdateInfo(
      version: version.join('.'),
      tag: tag,
      downloadUrl: url,
      notes: entry['body'] is String ? entry['body']! as String : '',
    );
  }

  return best;
}

/// 挑一个能装的 APK。
///
/// `pakem build` 走的是 `--split-per-abi`，一次出三个包
/// （arm64-v8a / armeabi-v7a / x86_64）——「取第一个 .apk」会按上传顺序
/// 随机发一个出去，而 x86_64 装到任何一台真手机上都是失败的。所以先认
/// `arm64-v8a`：现役 Android 手机几乎全是它。
///
/// 认不出 ABI 的（单个通用包）就退回全部 apk。
///
/// 剩下不止一个时再按 [appName] 筛一道：CI 的 `build-presets` 会把多个 app
/// 的包挂进同一条 release，asset 名带 app 名前缀
/// （`4KVM-app-arm64-v8a-release.apk`），只按 ABI 筛的话 DADATU 的用户会拿到
/// 4KVM 的包——applicationId 不同，那不是升级，是**静默装上另一个 app**。
///
/// 筛完还是拿不准（一个都不剩、或者剩好几个）就回落 release 页面让人自己挑。
/// 发错包比让人多点一下贵得多。
///
/// 残余代价：只剩 32 位的老设备会拿到一个装不上的 arm64 包。不为它引
/// `device_info_plus` 去读真实 ABI，那是给一类基本不存在的设备加一个依赖。
String _downloadUrl(Map<String, Object?> release, String appName) {
  final apks = <String, String>{};

  final assets = release['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map<String, Object?>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && name.endsWith('.apk') && url is String) {
        apks[name] = url;
      }
    }
  }

  var candidates = apks.keys.where((n) => n.contains('arm64-v8a')).toList();
  if (candidates.isEmpty) candidates = apks.keys.toList();

  if (candidates.length > 1 && appName.isNotEmpty) {
    final needle = appName.toLowerCase();
    final mine = candidates
        .where((n) => n.toLowerCase().contains(needle))
        .toList();
    if (mine.isNotEmpty) candidates = mine;
  }

  if (candidates.length == 1) return apks[candidates.single]!;

  final html = release['html_url'];
  return html is String ? html : '';
}
