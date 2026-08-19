import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/runtime_config.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  injectScripts: ['hide-ads.js'],
);

/// 64 个十六进制字符——长度是 `patternHash` getter 的校验条件之一。
const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // get_storage 在真机上靠 path_provider 找文档目录；单元测试没有原生插件
    // 通道，这里喂一个假实现，指向临时目录，跟被测逻辑本身无关。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_shell_test').path,
        );

    await GetStorage.init();
    await GetStorage().erase();
  });

  test('falls back to the build-time url when runtime is empty', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.url, 'https://m.weibo.cn');
  });

  test('a runtime write wins over the build-time default', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)
      ..url = 'https://other.com';

    expect(c.url, 'https://other.com');
    expect(
      RuntimeConfig.fromBuildTime(_buildTime).url,
      'https://other.com',
      reason: 'the write must persist across instances',
    );
  });

  test('writing runtime config never mutates the build-time layer', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)
      ..url = 'https://other.com';

    expect(c.buildTime.url, 'https://m.weibo.cn');
  });

  test('reset clears the runtime layer and falls back again', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)
      ..url = 'https://other.com'
      ..userAgent = 'custom-ua';

    c.reset();

    expect(c.url, 'https://m.weibo.cn');
    expect(
      c.userAgent,
      isEmpty,
      reason: 'empty means "use the system default"',
    );
  });

  test('all inject scripts are enabled by default, as ids not paths', () {
    // pake.json 存的是原始路径，`assets/scripts/index.json` 和 WebViewPage 用的
    // 是 id。默认集合放路径 = 一个脚本都注入不了，而且测试照样绿。
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.enabledScripts, {'hide-ads'});
  });

  test('the default set is id-shaped even for nested and absolute paths', () {
    final c = RuntimeConfig.fromBuildTime(
      const PakeConfig(
        name: 'Weibo',
        url: 'https://m.weibo.cn',
        bundleId: 'com.pake.weibo',
        injectScripts: ['scripts/theme.css', '/abs/dir/fix-video.js'],
      ),
    );

    expect(c.enabledScripts, {'theme', 'fix-video'});
  });

  test('toggling a script off persists', () {
    RuntimeConfig.fromBuildTime(_buildTime).setScriptEnabled('hide-ads', false);

    expect(RuntimeConfig.fromBuildTime(_buildTime).enabledScripts, isEmpty);
  });

  test('a corrupt stored value falls back instead of throwing', () {
    // spec 的错误处理明确要求：读到损坏配置回落默认，不崩溃。
    GetStorage().write(RuntimeKeys.url, 12345);
    GetStorage().write(RuntimeKeys.enabledScripts, 'not-a-list');

    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.url, 'https://m.weibo.cn');
    expect(c.enabledScripts, {'hide-ads'});
  });

  test('network capture is on by default but can be turned off', () {
    // net_hook 是唯一无条件注入的脚本——它替换页面的 fetch/XHR，
    // 出问题时用户必须能关掉它。
    expect(RuntimeConfig.fromBuildTime(_buildTime).captureNetwork, isTrue);

    RuntimeConfig.fromBuildTime(_buildTime).captureNetwork = false;

    expect(RuntimeConfig.fromBuildTime(_buildTime).captureNetwork, isFalse);
  });

  test('reset turns network capture back on', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)..captureNetwork = false;

    c.reset();

    expect(c.captureNetwork, isTrue);
  });

  test('a corrupt captureNetwork value falls back to on', () {
    GetStorage().write(RuntimeKeys.captureNetwork, 'yes-please');

    expect(RuntimeConfig.fromBuildTime(_buildTime).captureNetwork, isTrue);
  });

  test('userAgent defaults to empty, meaning the system default', () {
    expect(RuntimeConfig.fromBuildTime(_buildTime).userAgent, isEmpty);
  });

  test('reset leaves non-pake keys (debug_sheet input history) intact', () {
    // debug_sheet 把输入历史存在同一个默认容器里，键名不带 pake. 前缀。
    // reset() 必须只删自己的键，绝不能碰这些键——否则「重置设置」
    // 会顺手把用户在调试面板里敲过的 URL 历史也清掉。
    GetStorage().write('some-debug-sheet-history-key', ['typed-value']);

    RuntimeConfig.fromBuildTime(_buildTime).reset();

    expect(GetStorage().read('some-debug-sheet-history-key'), ['typed-value']);
  });

  test('the app lock is off until it is turned on', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.appLockEnabled, isFalse);
    expect(c.patternHash, isNull);
  });

  test('the pattern hash and the switch persist across instances', () {
    RuntimeConfig.fromBuildTime(_buildTime)
      ..appLockEnabled = true
      ..patternHash = _hash;

    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.appLockEnabled, isTrue);
    expect(c.patternHash, _hash);
  });

  test('a corrupt hash reads as unset instead of locking the user out', () {
    // 一个永远匹配不上的哈希就是把人永久锁在外面。宁可当没设过。
    GetStorage().write(RuntimeKeys.patternHash, 'not-a-hash');

    expect(RuntimeConfig.fromBuildTime(_buildTime).patternHash, isNull);
  });

  test('a non-string hash reads as unset too', () {
    GetStorage().write(RuntimeKeys.patternHash, 1234);

    expect(RuntimeConfig.fromBuildTime(_buildTime).patternHash, isNull);
  });

  test('reset clears the app lock', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)
      ..appLockEnabled = true
      ..patternHash = _hash;

    c.reset();

    expect(c.appLockEnabled, isFalse);
    expect(c.patternHash, isNull);
  });
}
