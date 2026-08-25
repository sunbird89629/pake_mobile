import 'permission.dart';

/// 从 `x.y.z` 推出 Android 的 versionCode / iOS 的 build number。
///
/// `1.0.0` → `10000`，`1.2.3` → `10203`。**系统只认这个数字**，认不出
/// versionName——只 bump version 而它不动的话，两个包在系统眼里一模一样，
/// 「这台手机上装的到底是哪个构建」就没法回答了。让它跟着 version 走，
/// 就不用记住「改版本号要顺手改两个字段」。
///
/// 代价：minor 和 patch 都必须小于 100，超了就会串位
/// （`1.0.100` 和 `1.1.0` 撞成同一个数）。三段语义化版本号里这两位到 100
/// 本来就该进位了。
///
/// **这不是装到手机上的最终值。** 构建走 `--split-per-abi`，Flutter 会再给
/// 每个 ABI 加偏移（v7a +1000 / arm64 +2000 / x86_64 +4000），所以 `1.0.0`
/// 的 arm64 包 `aapt` 读出来是 12000 而不是 10000——数对不上不是这里坏了。
/// 一台设备只装同一个 ABI，同 ABI 内单调性成立；跨 ABI 的数不可比。
/// 完整策略见 `docs/versioning.md`。
///
/// 解析不出来时回落 1——`validateConfig` 会先把非法 version 拦下，
/// 走到这里的都是 `x.y.z`。
int versionCodeFor(String version) {
  final parts = version.split('.');
  if (parts.length != 3) return 1;

  const weights = [10000, 100, 1];
  var code = 0;
  for (var i = 0; i < 3; i++) {
    final value = int.tryParse(parts[i]);
    if (value == null || value < 0) return 1;
    code += value * weights[i];
  }
  // 0.0.0 推出来是 0，而 versionCode 必须是正数。
  return code == 0 ? 1 : code;
}

/// 构建期配置。CLI 写，壳在启动时读作运行期默认值。
///
/// 运行期可改的项（当前 URL / UA / 脚本开关等）不在这里——见 [RuntimeKeys]。
class PakeConfig {
  const PakeConfig({
    required this.name,
    required this.url,
    required this.bundleId,
    this.version = '1.0.0',
    this.buildNumber,
    this.iconPath,
    this.injectScripts = const [],
    this.permissions = const [],
  });

  factory PakeConfig.fromJson(Map<String, Object?> json) {
    final rawScripts = json['injectScripts'] as List<Object?>? ?? const [];
    final rawPerms = json['permissions'] as List<Object?>? ?? const [];
    return PakeConfig(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      bundleId: json['bundleId'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int?,
      iconPath: json['iconPath'] as String?,
      injectScripts: rawScripts.map((e) => e! as String).toList(),
      permissions: rawPerms
          .map((e) => PakePermission.byName(e! as String))
          .whereType<PakePermission>()
          .toList(),
    );
  }

  final String name;
  final String url;
  final String bundleId;
  final String version;

  /// 显式钉死 versionCode 的后门：同一个 version 要重发一次包时用。
  /// 不写就由 [versionCodeFor] 从 version 推——那是常态。
  final int? buildNumber;

  /// 真正写进 `build.gradle.kts` 和 `--build-number` 的那个数。
  int get versionCode => buildNumber ?? versionCodeFor(version);
  final String? iconPath;
  final List<String> injectScripts;
  final List<PakePermission> permissions;

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'bundleId': bundleId,
    'version': version,
    if (buildNumber != null) 'buildNumber': buildNumber,
    if (iconPath != null) 'iconPath': iconPath,
    'injectScripts': injectScripts,
    'permissions': [for (final p in permissions) p.name],
  };

  PakeConfig copyWith({
    String? name,
    String? url,
    String? bundleId,
    String? version,
    int? buildNumber,
    String? iconPath,
    List<String>? injectScripts,
    List<PakePermission>? permissions,
  }) => PakeConfig(
    name: name ?? this.name,
    url: url ?? this.url,
    bundleId: bundleId ?? this.bundleId,
    version: version ?? this.version,
    buildNumber: buildNumber ?? this.buildNumber,
    iconPath: iconPath ?? this.iconPath,
    injectScripts: injectScripts ?? this.injectScripts,
    permissions: permissions ?? this.permissions,
  );

  @override
  bool operator ==(Object other) =>
      other is PakeConfig &&
      other.name == name &&
      other.url == url &&
      other.bundleId == bundleId &&
      other.version == version &&
      other.buildNumber == buildNumber &&
      other.iconPath == iconPath &&
      _listEq(other.injectScripts, injectScripts) &&
      _listEq(other.permissions, permissions);

  @override
  int get hashCode => Object.hash(
    name,
    url,
    bundleId,
    version,
    buildNumber,
    iconPath,
    Object.hashAll(injectScripts),
    Object.hashAll(permissions),
  );

  @override
  String toString() => 'PakeConfig($name, $bundleId, $url)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
