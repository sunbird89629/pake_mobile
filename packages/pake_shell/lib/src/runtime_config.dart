import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';

/// 两层配置的运行期视图。
///
/// 读：runtime 层有值就用，没有就回落 build-time 层。
/// 写：只写 runtime 层——build-time 层是 asset，物理上也改不了。
class RuntimeConfig {
  RuntimeConfig.fromBuildTime(this.buildTime);

  /// 从打进 assets 的 `pake.json` 载入构建期配置。
  static Future<RuntimeConfig> load() async {
    final raw = await rootBundle.loadString('assets/pake.json');
    return RuntimeConfig.fromBuildTime(
      PakeConfig.fromJson(jsonDecode(raw) as Map<String, Object?>),
    );
  }

  final PakeConfig buildTime;

  GetStorage get _box => GetStorage();

  String get url => _readString(RuntimeKeys.url) ?? buildTime.url;
  set url(String value) => _box.write(RuntimeKeys.url, value);

  /// 空串表示「用系统默认 UA」。
  String get userAgent => _readString(RuntimeKeys.userAgent) ?? '';
  set userAgent(String value) => _box.write(RuntimeKeys.userAgent, value);

  bool get fullscreen => _readBool(RuntimeKeys.fullscreen) ?? true;
  set fullscreen(bool value) => _box.write(RuntimeKeys.fullscreen, value);

  /// 抓包 hook 默认开——这个壳的用途之一就是看站点发了什么请求。
  /// 但它会 hook 掉页面的 fetch/XHR，出问题时必须能关。
  bool get captureNetwork => _readBool(RuntimeKeys.captureNetwork) ?? true;
  set captureNetwork(bool value) =>
      _box.write(RuntimeKeys.captureNetwork, value);

  /// 默认关。这是个网页壳，多数站点不需要锁——默认开会让所有现有用户
  /// 莫名其妙被挡在外面。
  bool get appLockEnabled => _readBool(RuntimeKeys.appLockEnabled) ?? false;
  set appLockEnabled(bool value) =>
      _box.write(RuntimeKeys.appLockEnabled, value);

  /// `null` = 没设过。读到非 int（人手改过、旧版本遗留）同样当没设——
  /// 一个残缺的存储状态不该把人锁在 app 外面。
  int? get pinCode {
    final value = _box.read<Object?>(RuntimeKeys.pinCode);
    return value is int ? value : null;
  }

  set pinCode(int? value) => value == null
      ? _box.remove(RuntimeKeys.pinCode)
      : _box.write(RuntimeKeys.pinCode, value);

  /// 默认全开——构建时特意打包进来的脚本，默认不生效才是意外。
  ///
  /// 集合里放的是 **id**（`scriptIdFor`），不是 `pake.json` 里的原始路径：
  /// `assets/scripts/index.json` 和设置页开关用的都是 id，这里放路径就等于
  /// 所有脚本永远匹配不上，一个都注入不了。
  Set<String> get enabledScripts {
    final stored = _box.read<Object?>(RuntimeKeys.enabledScripts);
    if (stored is! List) return defaultEnabledScripts(buildTime);
    return stored.whereType<String>().toSet();
  }

  void setScriptEnabled(String id, bool enabled) {
    final next = enabledScripts.toSet();
    enabled ? next.add(id) : next.remove(id);
    _box.write(RuntimeKeys.enabledScripts, next.toList());
  }

  /// 「重置」= 清空 runtime 层，回落构建时默认。
  ///
  /// 只删自己的键，不 `erase()`——那会连 `debug_sheet` 的输入历史一起清掉。
  void reset() {
    for (final key in const [
      RuntimeKeys.url,
      RuntimeKeys.userAgent,
      RuntimeKeys.enabledScripts,
      RuntimeKeys.logLevel,
      RuntimeKeys.fullscreen,
      RuntimeKeys.captureNetwork,
      RuntimeKeys.appLockEnabled,
      RuntimeKeys.pinCode,
    ]) {
      _box.remove(key);
    }
  }

  /// 存进去的值类型不对（人手改过、旧版本遗留）时回落，而不是抛异常。
  String? _readString(String key) {
    final value = _box.read<Object?>(key);
    return value is String && value.isNotEmpty ? value : null;
  }

  bool? _readBool(String key) {
    final value = _box.read<Object?>(key);
    return value is bool ? value : null;
  }
}
