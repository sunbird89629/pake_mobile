import 'permission.dart';

/// 构建期配置。CLI 写，壳在启动时读作运行期默认值。
///
/// 运行期可改的项（当前 URL / UA / 脚本开关等）不在这里——见 [RuntimeKeys]。
class PakeConfig {
  const PakeConfig({
    required this.name,
    required this.url,
    required this.bundleId,
    this.version = '1.0.0',
    this.buildNumber = 1,
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
      buildNumber: json['buildNumber'] as int? ?? 1,
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
  final int buildNumber;
  final String? iconPath;
  final List<String> injectScripts;
  final List<PakePermission> permissions;

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'bundleId': bundleId,
    'version': version,
    'buildNumber': buildNumber,
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
