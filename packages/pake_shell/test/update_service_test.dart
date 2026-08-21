import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/runtime_config.dart';
import 'package:pake_shell/src/update/update_service.dart';

const _buildTime = PakeConfig(
  name: '4KVM',
  url: 'https://www.4kvm.site',
  bundleId: 'com.pake.fourkvm',
  version: '1.0.0',
);

final _payload = jsonEncode([
  {
    'tag_name': 'fourkvm-v1.2.0',
    'draft': false,
    'prerelease': false,
    'body': '',
    'assets': [
      {'name': 'app.apk', 'browser_download_url': 'https://dl/app.apk'},
    ],
  },
]);

void main() {
  late RuntimeConfig config;
  late int calls;

  Future<String> ok(Uri _) async {
    calls++;
    return _payload;
  }

  Future<String> boom(Uri _) async {
    calls++;
    throw const SocketException('no route to host');
  }

  UpdateService service(Fetcher fetch, {DateTime? now}) =>
      UpdateService(config, fetch: fetch, now: now == null ? null : () => now);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // 同 runtime_config_test：单元测试没有原生插件通道，喂个假的给 get_storage。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('pake_update_test').path,
        );

    await GetStorage.init();
    await GetStorage().erase();

    config = RuntimeConfig.fromBuildTime(_buildTime);
    calls = 0;
  });

  test('finds an update on a cold start', () async {
    final info = await service(ok).checkOnLaunch();

    expect(info!.version, '1.2.0');
    expect(calls, 1);
  });

  test('does not fire at all when the switch is off', () async {
    config.updateCheckEnabled = false;

    expect(await service(ok).checkOnLaunch(), isNull);
    expect(calls, 0);
  });

  test('throttles the second launch within 24h', () async {
    final start = DateTime(2026, 8, 21, 10);

    expect(await service(ok, now: start).checkOnLaunch(), isNotNull);
    expect(
      await service(
        ok,
        now: start.add(const Duration(hours: 23)),
      ).checkOnLaunch(),
      isNull,
    );
    expect(calls, 1);

    expect(
      await service(
        ok,
        now: start.add(const Duration(hours: 25)),
      ).checkOnLaunch(),
      isNotNull,
    );
    expect(calls, 2);
  });

  // 网络失败也记时间戳的话，断网启动一次就把接下来 24 小时全吞掉。
  test('does not start the throttle window when the request failed', () async {
    expect(await service(boom).checkOnLaunch(), isNull);
    expect(config.lastUpdateCheckAt, isNull);

    expect(await service(ok).checkOnLaunch(), isNotNull);
    expect(calls, 2);
  });

  test('stays silent on any failure', () async {
    expect(await service(boom).checkOnLaunch(), isNull);
    expect(await service((_) async => 'not json').checkOnLaunch(), isNull);
  });

  test('hides a version the user dismissed, but only that one', () async {
    config.dismissedUpdateVersion = '1.2.0';
    expect(await service(ok).checkOnLaunch(), isNull);

    config
      ..dismissedUpdateVersion = '1.1.0'
      ..lastUpdateCheckAt = null;
    expect(await service(ok).checkOnLaunch(), isNotNull);
  });

  group('manual check', () {
    test('ignores both the switch and the throttle', () async {
      config
        ..updateCheckEnabled = false
        ..lastUpdateCheckAt = DateTime.now();

      expect((await service(ok).check())!.version, '1.2.0');
      expect(calls, 1);
    });

    test('lets errors through so the settings page can show them', () async {
      expect(service(boom).check(), throwsA(isA<SocketException>()));
    });

    test('shows a dismissed version again when asked directly', () async {
      config.dismissedUpdateVersion = '1.2.0';

      expect((await service(ok).check())!.version, '1.2.0');
    });
  });
}
