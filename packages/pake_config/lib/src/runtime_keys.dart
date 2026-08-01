/// `get_storage` 默认容器里的键名。
///
/// 全部带 `pake.` 前缀：`debug_sheet` 在同一个容器里用 `md5(title)` 存输入历史，
/// 前缀保证两者永不相撞。
abstract final class RuntimeKeys {
  static const url = 'pake.url';
  static const userAgent = 'pake.userAgent';
  static const enabledScripts = 'pake.enabledScripts';
  static const logLevel = 'pake.logLevel';
  static const fullscreen = 'pake.fullscreen';

  /// 抓包 hook 的开关。它是唯一无条件注入的脚本，没有这个键，用户就是
  /// 关不掉它——而它要 hook 掉页面的 fetch/XHR。
  static const captureNetwork = 'pake.captureNetwork';

  /// 应用锁的开关与 4 位 PIN。
  ///
  /// PIN 明文存 `int`——`PinLockScreen` 的比对在 widget 内部，必须拿到明文
  /// 才能用上它自带的错误反馈。威胁模型是「别人拿起我的手机」，不是取证。
  static const appLockEnabled = 'pake.appLockEnabled';
  static const pinCode = 'pake.pinCode';
}

/// 设置页「切 UA」的预设。`Default` 映射到空串，表示用系统默认 UA。
abstract final class UserAgentPresets {
  static const _iosSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _androidChrome =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _desktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Map<String, String> all = {
    'Default': '',
    'iOS Safari': _iosSafari,
    'Android Chrome': _androidChrome,
    'Desktop': _desktop,
  };
}
