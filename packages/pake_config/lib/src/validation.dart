import 'dart:io';

import 'config.dart';
import 'script_id.dart';

/// 一条配置错误。CLI 把它渲染成人类可读文本或 `--json` 的 error 数组。
class ConfigError {
  const ConfigError(this.field, this.message);

  final String field;
  final String message;

  Map<String, Object?> toJson() => {'field': field, 'message': message};

  @override
  String toString() => '$field: $message';
}

/// Android applicationId / iOS bundle id 的交集规则：
/// 至少两段，每段以字母开头，其余为字母数字下划线。
final _bundleIdPattern = RegExp(
  r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
);

final _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

/// 一次性返回**所有**问题，不在第一个错误处停下——用户改一次就该改全。
///
/// [fileExists] 可注入以便测试；默认走真实文件系统。
List<ConfigError> validateConfig(
  PakeConfig config, {
  bool Function(String path)? fileExists,
}) {
  final exists = fileExists ?? (String p) => File(p).existsSync();
  final errors = <ConfigError>[];

  if (config.name.trim().isEmpty) {
    errors.add(const ConfigError('name', 'App name must not be empty.'));
  }

  final uri = Uri.tryParse(config.url);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    errors.add(
      ConfigError(
        'url',
        'Must be an absolute http:// or https:// URL with a host, got "${config.url}".',
      ),
    );
  }

  if (!_bundleIdPattern.hasMatch(config.bundleId)) {
    errors.add(
      ConfigError(
        'bundleId',
        'Must be at least two dot-separated segments, each starting with a '
            'letter (e.g. com.example.app), got "${config.bundleId}".',
      ),
    );
  }

  if (!_versionPattern.hasMatch(config.version)) {
    errors.add(
      ConfigError(
        'version',
        'Must be x.y.z with numeric parts, got "${config.version}".',
      ),
    );
  }

  final icon = config.iconPath;
  if (icon != null && !exists(icon)) {
    errors.add(ConfigError('iconPath', 'Icon file not found: $icon'));
  }

  // 两个脚本推出同一个 id（`a/theme.js` 与 `b/theme.css` 都是 `theme`）时，
  // 后者会在物化目录里静默盖掉前者，运行期开关也只剩一个——必须在这里拦下。
  final idOwners = <String, String>{};
  for (final script in config.injectScripts) {
    if (!exists(script)) {
      errors.add(
        ConfigError('injectScripts', 'Inject file not found: $script'),
      );
    }

    final id = scriptIdFor(script);
    final owner = idOwners[id];
    if (owner != null) {
      errors.add(
        ConfigError(
          'injectScripts',
          'Duplicate script id "$id": "$owner" and "$script" would overwrite '
              'each other. Rename one of them.',
        ),
      );
    } else {
      idOwners[id] = script;
    }
  }

  return errors;
}
