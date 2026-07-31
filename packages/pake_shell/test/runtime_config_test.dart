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

  test('all inject scripts are enabled by default', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.enabledScripts, {'hide-ads.js'});
  });

  test('toggling a script off persists', () {
    RuntimeConfig.fromBuildTime(
      _buildTime,
    ).setScriptEnabled('hide-ads.js', false);

    expect(RuntimeConfig.fromBuildTime(_buildTime).enabledScripts, isEmpty);
  });

  test('a corrupt stored value falls back instead of throwing', () {
    // spec 的错误处理明确要求：读到损坏配置回落默认，不崩溃。
    GetStorage().write(RuntimeKeys.url, 12345);
    GetStorage().write(RuntimeKeys.enabledScripts, 'not-a-list');

    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.url, 'https://m.weibo.cn');
    expect(c.enabledScripts, {'hide-ads.js'});
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
}
