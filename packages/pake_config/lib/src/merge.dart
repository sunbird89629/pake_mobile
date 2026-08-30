import 'config.dart';
import 'permission.dart';

/// CLI flag 解析结果。全部可空——`null` 表示「用户没给这个 flag」，
/// 与「用户显式给了空值」（如 `--inject` 一个都不给）区分开。
class PakeFlags {
  const PakeFlags({
    this.name,
    this.url,
    this.bundleId,
    this.version,
    this.description,
    this.buildNumber,
    this.iconPath,
    this.injectScripts,
    this.permissions,
  });

  final String? name;
  final String? url;
  final String? bundleId;
  final String? version;
  final String? description;
  final int? buildNumber;
  final String? iconPath;
  final List<String>? injectScripts;
  final List<PakePermission>? permissions;
}

/// 合并优先级：flags > fileJson > 模型默认值。
///
/// 注意这里**不做校验**——校验是 [validateConfig] 的事，
/// 好让 CLI 能先把三个来源拼完整，再一次性报出所有问题。
PakeConfig mergeConfig({Map<String, Object?>? fileJson, PakeFlags? flags}) {
  final base = PakeConfig.fromJson(fileJson ?? const {});
  if (flags == null) return base;

  return base.copyWith(
    name: flags.name,
    url: flags.url,
    bundleId: flags.bundleId,
    version: flags.version,
    description: flags.description,
    buildNumber: flags.buildNumber,
    iconPath: flags.iconPath,
    injectScripts: flags.injectScripts,
    permissions: flags.permissions,
  );
}
