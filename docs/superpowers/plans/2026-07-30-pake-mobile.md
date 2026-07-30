---
title: "pake_mobile 实现计划"
date: 2026-07-30
spec: ../specs/2026-07-30-pake-mobile-design.md
---

# pake_mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用一套 Dart 代码库把任意网页打包成 Android APK 与 iOS IPA，`pakem` CLI 是唯一构建入口。

**Architecture:** 三个包。`pake_config` 是纯 Dart 共享层，定义构建期配置模型、校验规则、运行期存储键——CLI 写它，壳读它，schema 物理上不可能漂移。`pake_cli` 把配置物化进一个常驻的固定 workspace（保住 Flutter 增量缓存）再调 `flutter build`。`pake_shell` 是 Flutter 模板壳：全屏 `InAppWebView` + 角落逃生手势 + 运行时设置抽屉。

**Tech Stack:** Flutter 3.41.2 / Dart 3.11.0 · `flutter_inappwebview` 6.2.0-beta.3 · `get_storage` 2.1.1 · 自有包 `debug_sheet` / `logger_utils`（均为 public git dependency，未发布 pub.dev）

## Global Constraints

- Dart SDK 约束一律 `^3.8.0`；Flutter 约束一律 `>=3.32.0`。这是 `flutter_inappwebview` 6.2.0-beta.3 的下限，本机 Dart 3.11.0 / Flutter 3.41.2 满足。
- 三个自有包**都没有发布到 pub.dev**（已验证均返回 404），必须写 git dependency：
  - `debug_sheet` → `https://github.com/sunbird89629/debug_sheet.git`
  - `logger_utils` → `https://github.com/sunbird89629/logger_utils.git`
  - 三个仓库均为 public（GitHub API 返回 200），CI 拉取无需凭据。
- **不引入 `flutter_ci_tools`**（偏离 spec，理由见下方「与 spec 的偏离」）。
- 可执行名 `pakem`。退出码：`1` 配置错误 / `2` 环境缺失 / `3` 构建失败。
- `--platform` 默认 `android`，即便在 macOS 上也不默认双端。
- 配置查找顺序不叠加：`--config <path>` > 当前目录 `pake.json` > 无文件；CLI flag 始终覆盖文件同名字段。
- 运行期配置只用 `get_storage` 默认容器（`GetStorage()`），因为 `debug_sheet` 内部就写死了默认容器。
- 所有物化逻辑必须是**纯字符串函数**（`String patchX(String original, PakeConfig c)`），以便 golden test 秒级跑完、不碰真实 workspace。
- 长字符串一律用反引号模板字符串（Dart 中即 `'''` 原始多行字符串），不用 `+` 拼接。

## 探查结论（已解掉 spec 的两条未决事项）

**未决事项 1 — `http_inspector` UI 不可复用，自建面板。** 已读源码确认：`lib/src/models/network/http_record.dart` 自身 import dio，而全部 16 个 UI widget 都依赖 `HttpRecord` 模型 + `MainProvider()` 全局单例。解耦成本高于重写。沿用其信息布局（列表 + 详情 + cURL 导出），代码自己写。

**未决事项 2 — fork ref 跟 `master`，但 day-1 不 fork。** 本地 clone 已在 `master`（含 `6.2.0-beta.3`），pubspec 约束与本机工具链兼容。直接用 pub.dev 的 `6.2.0-beta.3` 起步；遇坑再切 fork。

> **fork 时的关键细节（现在别做，遇坑再查回这段）**：`flutter_inappwebview` 主包只是薄壳，实现在 `flutter_inappwebview_android` / `_ios` / `_platform_interface` 里，且主包 pubspec 里这些子包的 `path:` 依赖是**注释掉的**、走 pub.dev。所以单独 fork 主包改不到原生代码。必须在 `pake_shell/pubspec.yaml` 写 `dependency_overrides`，把主包 + `_platform_interface` + `_android` + `_ios` 四个一起指向 fork 仓库的对应子目录（`git: {url: ..., path: flutter_inappwebview_android}`）。`_macos` / `_web` / `_windows` / `_linux` 不构建，保持 pub.dev 版本即可。

## 与 spec 的偏离

**不引入 `flutter_ci_tools`。** spec「技术选型」表列它为「构建编排 / 版本号，CLI 侧复用」。实际读源码后：它的 API 形状是 `PipelineAction.run(PipelineContext context)` 框架，复用意味着 `pake_cli` 的整条流水线要套进它的 context/registry 抽象，比直接写 4 个函数复杂得多；而版本号本就由 `pake.json` / `--version` flag 直接给定，`ResolveBuildVersionAction` 那套 git tag 推导在此场景无用武之地。这是 YAGNI 判断，不是遗漏。

## 依赖包的真实 API（写代码前必读，签名已从源码核对）

```dart
// logger_utils —— 纯 Dart，CLI 与壳共用
void initLogging({String? logsDir, String filePrefix = 'app'});
final Logger devLogger;  // 来自 package:logging

// debug_sheet —— 注意：是 Widget，不是 static show 方法
class DebugInputSheet extends StatefulWidget {
  const DebugInputSheet({super.key, required this.title});
}   // Navigator.pop 返回 String?（输入为空时返回 null）

class DebugSelectSheet extends StatefulWidget {
  const DebugSelectSheet({super.key, required this.title, required this.items});
}   // Navigator.pop 返回 int（选中索引）
```

**三个必须绕开的集成坑：**

1. `DebugInputSheet` 内部用了 `Expanded` + `ListView`，**必须给有界高度**，否则布局崩。调用时包一层：`showModalBottomSheet(isScrollControlled: true, builder: (_) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.6, child: DebugInputSheet(...)))`。
2. `DebugSelectSheet` **没有 `initialIndex` 参数**，`_selectedIndex` 恒从 0 起。切 UA 时无法预选当前值。绕法：调用前把当前值重排到 `items[0]`，零改动上游包。
3. 两者都可能被下滑手势取消，`showModalBottomSheet` 返回 `null`。调用方必须处理 null，不能 `!`。
4. `DebugInputSheet` 的历史记录直接写 `GetStorage()` 默认容器，key 是 `md5(title)`。所以 `GetStorage.init()` 必须在 `runApp` 前完成。

## File Structure

```
pake_mobile/
├── packages/
│   ├── pake_config/                      纯 Dart，无 Flutter 依赖
│   │   ├── lib/pake_config.dart          barrel
│   │   ├── lib/src/config.dart           PakeConfig 模型 + 序列化
│   │   ├── lib/src/permission.dart       PakePermission enum + 平台字符串
│   │   ├── lib/src/validation.dart       校验规则 + ConfigError
│   │   ├── lib/src/merge.dart            flags > pake.json > defaults
│   │   └── lib/src/runtime_keys.dart     get_storage 键常量（CLI 与壳共享）
│   ├── pake_cli/                         纯 Dart
│   │   ├── bin/pakem.dart                入口，退出码分级
│   │   ├── lib/src/runner.dart           CommandRunner 装配
│   │   ├── lib/src/commands/init.dart
│   │   ├── lib/src/commands/build.dart
│   │   ├── lib/src/commands/doctor.dart
│   │   ├── lib/src/commands/icon.dart
│   │   ├── lib/src/workspace.dart        ~/.pake/workspace + .lock
│   │   ├── lib/src/patch/android.dart    纯函数：patchBuildGradle / patchAndroidManifest
│   │   ├── lib/src/patch/ios.dart        纯函数：patchInfoPlist / exportOptionsPlist
│   │   ├── lib/src/patch/scripts.dart    纯函数：wrapUserScript
│   │   ├── lib/src/process_runner.dart   可注入的进程执行抽象（测试用 fake）
│   │   ├── lib/src/signing.dart          iOS 证书 / profile 前置检查
│   │   └── lib/src/output.dart           人类可读 / --json 双通道输出
│   └── pake_shell/                       Flutter app
│       ├── lib/main.dart
│       ├── lib/src/runtime_config.dart   两层配置的运行期读写
│       ├── lib/src/app.dart              PakeApp + Stack 组装
│       ├── lib/src/webview_page.dart
│       ├── lib/src/escape_hatch.dart
│       ├── lib/src/error_page.dart
│       ├── lib/src/debug_drawer.dart
│       ├── lib/src/net/net_record.dart   模型 + toCurl
│       ├── lib/src/net/net_log.dart      环形缓冲
│       ├── lib/src/net/net_hook.js       注入的 fetch/XHR 包装
│       └── lib/src/net/net_log_page.dart 列表 + 详情面板
└── .github/workflows/build.yml
```

---

### Task 1: 仓库骨架 + PakeConfig 模型与序列化往返

**Files:**
- Create: `packages/pake_config/pubspec.yaml`
- Create: `packages/pake_config/lib/pake_config.dart`
- Create: `packages/pake_config/lib/src/permission.dart`
- Create: `packages/pake_config/lib/src/config.dart`
- Test: `packages/pake_config/test/config_test.dart`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `PakeConfig`（字段 `name` / `url` / `bundleId` / `version` / `buildNumber` / `iconPath` / `injectScripts` / `permissions`），`PakeConfig.fromJson(Map<String, Object?>)`，`Map<String, Object?> toJson()`，`PakeConfig copyWith({...})`，`enum PakePermission { camera, microphone, location }` 及其 `androidPermission` / `iosUsageKey` / `iosUsageDescription` getter。

- [ ] **Step 1: 建包骨架**

`packages/pake_config/pubspec.yaml`：

```yaml
name: pake_config
description: Shared configuration model for pake_mobile — written by pake_cli, read by pake_shell.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 2: 写失败的测试**

`packages/pake_config/test/config_test.dart`：

```dart
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  group('PakeConfig', () {
    test('serialization round-trips all fields', () {
      const original = PakeConfig(
        name: 'Demo',
        url: 'https://example.com',
        bundleId: 'com.example.demo',
        version: '1.2.3',
        buildNumber: 7,
        iconPath: 'assets/icon.png',
        injectScripts: ['a.js', 'b.css'],
        permissions: [PakePermission.camera, PakePermission.location],
      );

      final restored = PakeConfig.fromJson(original.toJson());

      expect(restored, equals(original));
    });

    test('fromJson applies defaults for omitted optional fields', () {
      final c = PakeConfig.fromJson({
        'name': 'Minimal',
        'url': 'https://example.com',
        'bundleId': 'com.example.minimal',
      });

      expect(c.version, '1.0.0');
      expect(c.buildNumber, 1);
      expect(c.iconPath, isNull);
      expect(c.injectScripts, isEmpty);
      expect(c.permissions, isEmpty);
    });

    test('copyWith replaces only the named field', () {
      const c = PakeConfig(
        name: 'Demo',
        url: 'https://example.com',
        bundleId: 'com.example.demo',
      );

      expect(c.copyWith(url: 'https://other.com').url, 'https://other.com');
      expect(c.copyWith(url: 'https://other.com').name, 'Demo');
    });

    test('permission maps to platform-specific identifiers', () {
      expect(
        PakePermission.camera.androidPermission,
        'android.permission.CAMERA',
      );
      expect(PakePermission.camera.iosUsageKey, 'NSCameraUsageDescription');
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd packages/pake_config && dart pub get && dart test`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_config/pake_config.dart'`

- [ ] **Step 4: 实现 permission.dart**

```dart
/// 系统权限。必须在构建期声明——这是平台约束，不是设计选择。
enum PakePermission {
  camera,
  microphone,
  location;

  static PakePermission? byName(String name) {
    for (final p in PakePermission.values) {
      if (p.name == name) return p;
    }
    return null;
  }

  String get androidPermission => switch (this) {
        PakePermission.camera => 'android.permission.CAMERA',
        PakePermission.microphone => 'android.permission.RECORD_AUDIO',
        PakePermission.location => 'android.permission.ACCESS_FINE_LOCATION',
      };

  String get iosUsageKey => switch (this) {
        PakePermission.camera => 'NSCameraUsageDescription',
        PakePermission.microphone => 'NSMicrophoneUsageDescription',
        PakePermission.location => 'NSLocationWhenInUseUsageDescription',
      };

  String get iosUsageDescription => switch (this) {
        PakePermission.camera => 'This app uses the camera on the loaded page.',
        PakePermission.microphone =>
          'This app uses the microphone on the loaded page.',
        PakePermission.location =>
          'This app uses your location on the loaded page.',
      };
}
```

- [ ] **Step 5: 实现 config.dart**

```dart
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
  }) =>
      PakeConfig(
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
```

- [ ] **Step 6: 写 barrel 文件**

`packages/pake_config/lib/pake_config.dart`：

```dart
/// Shared configuration model — pake_cli writes it, pake_shell reads it.
library;

export 'src/config.dart';
export 'src/permission.dart';
```

- [ ] **Step 7: 跑测试确认通过**

Run: `cd packages/pake_config && dart test`
Expected: PASS，4 个测试全绿

- [ ] **Step 8: 提交**

```bash
git add packages/pake_config docs/superpowers/plans
git commit -m "feat(config): add PakeConfig model with serialization round-trip"
```

---

### Task 2: 配置校验

**Files:**
- Create: `packages/pake_config/lib/src/validation.dart`
- Modify: `packages/pake_config/lib/pake_config.dart`（加一行 export）
- Test: `packages/pake_config/test/validation_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `PakeConfig`
- Produces: `class ConfigError { final String field; final String message; }`，`List<ConfigError> validateConfig(PakeConfig config, {bool Function(String path)? fileExists})`。`fileExists` 是可注入探针，默认走真实文件系统；测试传 fake 以免碰磁盘。

**Why 校验必须在 CLI 前置：** spec 明确要求「配置错误须在亚秒级报出，不得由 Gradle 充当校验器」。一个 bundle id 拼错让用户等三分钟 Gradle 才报错，是最糟的体验。

- [ ] **Step 1: 写失败的测试**

`packages/pake_config/test/validation_test.dart`：

```dart
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

PakeConfig _valid({
  String name = 'Demo',
  String url = 'https://example.com',
  String bundleId = 'com.example.demo',
  String version = '1.0.0',
  String? iconPath,
  List<String> injectScripts = const [],
}) =>
    PakeConfig(
      name: name,
      url: url,
      bundleId: bundleId,
      version: version,
      iconPath: iconPath,
      injectScripts: injectScripts,
    );

/// 除显式列出的路径外都不存在。
bool Function(String) _fsWith(Set<String> present) => present.contains;

void main() {
  group('validateConfig', () {
    test('accepts a fully valid config', () {
      expect(validateConfig(_valid(), fileExists: _fsWith({})), isEmpty);
    });

    test('rejects a blank name', () {
      final errors = validateConfig(_valid(name: '  '), fileExists: _fsWith({}));
      expect(errors.map((e) => e.field), contains('name'));
    });

    test('rejects non-http schemes', () {
      for (final bad in ['ftp://example.com', 'file:///tmp/a.html', 'nonsense']) {
        final errors = validateConfig(_valid(url: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('url'), reason: bad);
      }
    });

    test('rejects a url without a host', () {
      final errors =
          validateConfig(_valid(url: 'https://'), fileExists: _fsWith({}));
      expect(errors.map((e) => e.field), contains('url'));
    });

    test('rejects malformed bundle ids', () {
      for (final bad in ['nodots', 'com..example', '1com.example', 'com.exa mple', 'com.example-app']) {
        final errors =
            validateConfig(_valid(bundleId: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('bundleId'), reason: bad);
      }
    });

    test('accepts bundle ids with underscores and digits after the first char', () {
      for (final ok in ['com.example.app2', 'com.my_org.demo_app']) {
        final errors =
            validateConfig(_valid(bundleId: ok), fileExists: _fsWith({}));
        expect(errors, isEmpty, reason: ok);
      }
    });

    test('rejects a version that is not x.y.z', () {
      for (final bad in ['1.0', 'v1.0.0', '1.0.0-beta']) {
        final errors =
            validateConfig(_valid(version: bad), fileExists: _fsWith({}));
        expect(errors.map((e) => e.field), contains('version'), reason: bad);
      }
    });

    test('rejects a missing icon file', () {
      final errors = validateConfig(
        _valid(iconPath: 'missing.png'),
        fileExists: _fsWith({}),
      );
      expect(errors.map((e) => e.field), contains('iconPath'));
    });

    test('accepts an icon file that exists', () {
      final errors = validateConfig(
        _valid(iconPath: 'icon.png'),
        fileExists: _fsWith({'icon.png'}),
      );
      expect(errors, isEmpty);
    });

    test('reports each unreadable inject script separately', () {
      final errors = validateConfig(
        _valid(injectScripts: ['there.js', 'gone.js', 'alsogone.css']),
        fileExists: _fsWith({'there.js'}),
      );
      expect(errors.length, 2);
      expect(errors.every((e) => e.field == 'injectScripts'), isTrue);
      expect(errors.map((e) => e.message).join(), contains('gone.js'));
    });

    test('reports every problem at once rather than stopping at the first', () {
      final errors = validateConfig(
        _valid(name: '', url: 'nonsense', bundleId: 'bad'),
        fileExists: _fsWith({}),
      );
      expect(errors.map((e) => e.field), containsAll(['name', 'url', 'bundleId']));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_config && dart test test/validation_test.dart`
Expected: FAIL — `Undefined name 'validateConfig'`

- [ ] **Step 3: 实现 validation.dart**

```dart
import 'dart:io';

import 'config.dart';

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
final _bundleIdPattern =
    RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');

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
    errors.add(ConfigError(
      'url',
      'Must be an absolute http:// or https:// URL with a host, got "${config.url}".',
    ));
  }

  if (!_bundleIdPattern.hasMatch(config.bundleId)) {
    errors.add(ConfigError(
      'bundleId',
      'Must be at least two dot-separated segments, each starting with a '
          'letter (e.g. com.example.app), got "${config.bundleId}".',
    ));
  }

  if (!_versionPattern.hasMatch(config.version)) {
    errors.add(ConfigError(
      'version',
      'Must be x.y.z with numeric parts, got "${config.version}".',
    ));
  }

  final icon = config.iconPath;
  if (icon != null && !exists(icon)) {
    errors.add(ConfigError('iconPath', 'Icon file not found: $icon'));
  }

  for (final script in config.injectScripts) {
    if (!exists(script)) {
      errors.add(
        ConfigError('injectScripts', 'Inject file not found: $script'),
      );
    }
  }

  return errors;
}
```

- [ ] **Step 4: 加 export**

在 `packages/pake_config/lib/pake_config.dart` 的 export 列表里加一行：

```dart
export 'src/validation.dart';
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_config && dart test`
Expected: PASS，全部测试绿

- [ ] **Step 6: 提交**

```bash
git add packages/pake_config
git commit -m "feat(config): validate url, bundle id, version, icon and inject files"
```

---

### Task 3: 配置合并优先级 + 运行期键常量

**Files:**
- Create: `packages/pake_config/lib/src/merge.dart`
- Create: `packages/pake_config/lib/src/runtime_keys.dart`
- Modify: `packages/pake_config/lib/pake_config.dart`（加两行 export）
- Test: `packages/pake_config/test/merge_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `PakeConfig` / `PakePermission`
- Produces:
  - `class PakeFlags`（全可空字段：`name` / `url` / `bundleId` / `version` / `buildNumber` / `iconPath` / `injectScripts` / `permissions`）
  - `PakeConfig mergeConfig({Map<String, Object?>? fileJson, PakeFlags? flags})`
  - `abstract final class RuntimeKeys`，常量 `url` / `userAgent` / `enabledScripts` / `logLevel` / `fullscreen`
  - `abstract final class UserAgentPresets`，`Map<String, String> get all`

**为何两个常量类放在 pake_config：** 运行期键名同时被 `pake_shell`（读写）与将来可能的 CLI 调试命令引用。放在共享包里，改名时编译器会同时报两边——这正是「CLI 用 Dart 而非 Node」的核心理由的延伸。

- [ ] **Step 1: 写失败的测试**

`packages/pake_config/test/merge_test.dart`：

```dart
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  group('mergeConfig', () {
    test('flags override same-named fields in the file', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'FromFile',
          'url': 'https://file.example.com',
          'bundleId': 'com.example.fromfile',
        },
        flags: const PakeFlags(url: 'https://flag.example.com'),
      );

      expect(merged.url, 'https://flag.example.com');
      expect(merged.name, 'FromFile', reason: 'unspecified flags must not clobber');
      expect(merged.bundleId, 'com.example.fromfile');
    });

    test('works with flags only when no file is present', () {
      final merged = mergeConfig(
        flags: const PakeFlags(
          name: 'FlagsOnly',
          url: 'https://example.com',
          bundleId: 'com.example.flagsonly',
        ),
      );

      expect(merged.name, 'FlagsOnly');
      expect(merged.version, '1.0.0', reason: 'falls back to model default');
    });

    test('works with a file only when no flags are given', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'FileOnly',
          'url': 'https://example.com',
          'bundleId': 'com.example.fileonly',
          'version': '2.0.0',
        },
      );

      expect(merged.name, 'FileOnly');
      expect(merged.version, '2.0.0');
    });

    test('an empty --inject list still overrides the file list', () {
      final merged = mergeConfig(
        fileJson: {
          'name': 'D',
          'url': 'https://example.com',
          'bundleId': 'com.example.d',
          'injectScripts': ['from-file.js'],
        },
        flags: const PakeFlags(injectScripts: []),
      );

      expect(merged.injectScripts, isEmpty);
    });

    test('produces an empty config when given neither source', () {
      final merged = mergeConfig();
      expect(merged.name, isEmpty);
      expect(merged.url, isEmpty);
    });
  });

  group('RuntimeKeys', () {
    test('keys are namespaced so they cannot collide with debug_sheet history', () {
      // debug_sheet 用 md5(title) 当 key（32 位十六进制），
      // 加前缀即可保证永不相撞。
      for (final k in [
        RuntimeKeys.url,
        RuntimeKeys.userAgent,
        RuntimeKeys.enabledScripts,
        RuntimeKeys.logLevel,
        RuntimeKeys.fullscreen,
      ]) {
        expect(k, startsWith('pake.'));
      }
    });
  });

  group('UserAgentPresets', () {
    test('exposes the four presets named in the design', () {
      expect(
        UserAgentPresets.all.keys,
        containsAll(['iOS Safari', 'Android Chrome', 'Desktop', 'Default']),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_config && dart test test/merge_test.dart`
Expected: FAIL — `Undefined name 'mergeConfig'`

- [ ] **Step 3: 实现 merge.dart**

```dart
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
    this.buildNumber,
    this.iconPath,
    this.injectScripts,
    this.permissions,
  });

  final String? name;
  final String? url;
  final String? bundleId;
  final String? version;
  final int? buildNumber;
  final String? iconPath;
  final List<String>? injectScripts;
  final List<PakePermission>? permissions;
}

/// 合并优先级：flags > fileJson > 模型默认值。
///
/// 注意这里**不做校验**——校验是 [validateConfig] 的事，
/// 好让 CLI 能先把三个来源拼完整，再一次性报出所有问题。
PakeConfig mergeConfig({
  Map<String, Object?>? fileJson,
  PakeFlags? flags,
}) {
  final base = PakeConfig.fromJson(fileJson ?? const {});
  if (flags == null) return base;

  return base.copyWith(
    name: flags.name,
    url: flags.url,
    bundleId: flags.bundleId,
    version: flags.version,
    buildNumber: flags.buildNumber,
    iconPath: flags.iconPath,
    injectScripts: flags.injectScripts,
    permissions: flags.permissions,
  );
}
```

- [ ] **Step 4: 实现 runtime_keys.dart**

```dart
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
```

- [ ] **Step 5: 加 export**

在 `packages/pake_config/lib/pake_config.dart` 加两行：

```dart
export 'src/merge.dart';
export 'src/runtime_keys.dart';
```

- [ ] **Step 6: 跑测试确认通过**

Run: `cd packages/pake_config && dart test`
Expected: PASS，全部测试绿

- [ ] **Step 7: 提交**

```bash
git add packages/pake_config
git commit -m "feat(config): add flag merge precedence and shared runtime keys"
```

---

### Task 4: CLI 骨架 —— 退出码分级、双通道输出、`pakem init`

**Files:**
- Create: `packages/pake_cli/pubspec.yaml`
- Create: `packages/pake_cli/lib/src/output.dart`
- Create: `packages/pake_cli/lib/src/commands/init.dart`
- Create: `packages/pake_cli/lib/src/runner.dart`
- Create: `packages/pake_cli/bin/pakem.dart`
- Test: `packages/pake_cli/test/output_test.dart`
- Test: `packages/pake_cli/test/init_test.dart`

**Interfaces:**
- Consumes: Task 1–3 的 `PakeConfig` / `ConfigError` / `validateConfig`
- Produces:
  - `class PakeException implements Exception { PakeException(this.exitCode, this.message, {this.details}); final int exitCode; final String message; final List<ConfigError> details; }`
  - `abstract final class ExitCodes { static const config = 1; static const environment = 2; static const build = 3; }`
  - `class Output { Output({required this.json, IOSink? sink}); void info(String line); void success(Map<String, Object?> payload); void failure(PakeException e); }`
  - `CommandRunner<int> buildRunner()`（后续任务往里 `addCommand`）

**设计要点：** `Output` 是**唯一**的写终端出口。人类模式下 `info` 逐行打印、`success` 打印友好摘要；`--json` 模式下 `info` 全部丢弃（否则污染 JSON），只在最后吐一个 JSON 对象。这样「`--json` 输出单个 JSON 对象」的契约由类型系统保证，而不是靠每个命令自觉。

- [ ] **Step 1: 建包骨架**

`packages/pake_cli/pubspec.yaml`：

```yaml
name: pake_cli
description: pakem — build any web page into an Android APK or iOS IPA.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

executables:
  pakem: pakem

dependencies:
  args: ^2.5.0
  path: ^1.9.0
  pake_config:
    path: ../pake_config
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 2: 写 output 的失败测试**

`packages/pake_cli/test/output_test.dart`：

```dart
import 'dart:convert';

import 'package:pake_cli/src/output.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

/// 收集写入内容的假 sink。
class _Buffer implements StringSink {
  final buffer = StringBuffer();
  @override
  void write(Object? obj) => buffer.write(obj);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);
  @override
  void writeln([Object? obj = '']) => buffer.writeln(obj);
}

void main() {
  group('Output in human mode', () {
    test('prints info lines', () {
      final b = _Buffer();
      Output(json: false, sink: b).info('building');
      expect(b.buffer.toString(), contains('building'));
    });

    test('prints a readable summary on success', () {
      final b = _Buffer();
      Output(json: false, sink: b).success({'artifacts': ['/tmp/app.apk']});
      expect(b.buffer.toString(), contains('/tmp/app.apk'));
      expect(b.buffer.toString(), isNot(startsWith('{')));
    });
  });

  group('Output in json mode', () {
    test('discards info lines so they cannot corrupt the json', () {
      final b = _Buffer();
      Output(json: true, sink: b).info('noise');
      expect(b.buffer.toString(), isEmpty);
    });

    test('emits exactly one json object on success', () {
      final b = _Buffer();
      Output(json: true, sink: b)
        ..info('noise')
        ..success({'artifacts': ['/tmp/app.apk']});

      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
      expect((decoded['artifacts']! as List).first, '/tmp/app.apk');
    });

    test('emits a json error object carrying the exit code and details', () {
      final b = _Buffer();
      Output(json: true, sink: b).failure(
        PakeException(
          ExitCodes.config,
          'invalid config',
          details: const [ConfigError('url', 'must be http(s)')],
        ),
      );

      final decoded = jsonDecode(b.buffer.toString()) as Map<String, Object?>;
      expect(decoded['ok'], isFalse);
      final error = decoded['error']! as Map<String, Object?>;
      expect(error['exitCode'], 1);
      expect(error['message'], 'invalid config');
      expect((error['details']! as List).first, {
        'field': 'url',
        'message': 'must be http(s)',
      });
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd packages/pake_cli && dart pub get && dart test test/output_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/output.dart'`

- [ ] **Step 4: 实现 output.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';

/// 退出码分级——agent 靠它编程处置，不必解析文本。
abstract final class ExitCodes {
  static const config = 1;
  static const environment = 2;
  static const build = 3;
}

/// 携带退出码的失败。CLI 顶层捕获它并交给 [Output.failure]。
class PakeException implements Exception {
  PakeException(this.exitCode, this.message, {this.details = const []});

  final int exitCode;
  final String message;
  final List<ConfigError> details;

  @override
  String toString() => message;
}

/// 唯一的终端出口。
///
/// `--json` 模式下 [info] 被丢弃——进度噪音会污染那个单一 JSON 对象，
/// 而 spec 承诺 `--json` 只输出一个对象。
class Output {
  Output({required this.json, StringSink? sink}) : _sink = sink ?? stdout;

  final bool json;
  final StringSink _sink;

  void info(String line) {
    if (json) return;
    _sink.writeln(line);
  }

  void success(Map<String, Object?> payload) {
    if (json) {
      _sink.write(jsonEncode({'ok': true, ...payload}));
      return;
    }
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value is List) {
        _sink.writeln('${entry.key}:');
        for (final item in value) {
          _sink.writeln('  $item');
        }
      } else {
        _sink.writeln('${entry.key}: $value');
      }
    }
  }

  void failure(PakeException e) {
    if (json) {
      _sink.write(jsonEncode({
        'ok': false,
        'error': {
          'exitCode': e.exitCode,
          'message': e.message,
          'details': [for (final d in e.details) d.toJson()],
        },
      }));
      return;
    }
    _sink.writeln('error: ${e.message}');
    for (final d in e.details) {
      _sink.writeln('  - $d');
    }
  }
}
```

- [ ] **Step 5: 写 init 的失败测试**

`packages/pake_cli/test/init_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/commands/init.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_init'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('writes a pake.json template that parses back into a PakeConfig', () {
    writeInitTemplate(tmp.path);

    final file = File('${tmp.path}/pake.json');
    expect(file.existsSync(), isTrue);

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final config = PakeConfig.fromJson(decoded);

    expect(config.name, isNotEmpty);
    expect(validateConfig(config, fileExists: (_) => true), isEmpty,
        reason: 'the template we ship must itself be valid');
  });

  test('refuses to clobber an existing pake.json', () {
    File('${tmp.path}/pake.json').writeAsStringSync('{"name":"mine"}');

    expect(
      () => writeInitTemplate(tmp.path),
      throwsA(isA<PakeException>()
          .having((e) => e.exitCode, 'exitCode', ExitCodes.config)),
    );

    expect(File('${tmp.path}/pake.json').readAsStringSync(), contains('mine'));
  });
}
```

- [ ] **Step 6: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/init_test.dart`
Expected: FAIL — `Undefined name 'writeInitTemplate'`

- [ ] **Step 7: 实现 init.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../output.dart';

/// 模板内容独立成函数，好让测试不经过 CommandRunner 直接验。
void writeInitTemplate(String directory) {
  final file = File(p.join(directory, 'pake.json'));
  if (file.existsSync()) {
    throw PakeException(
      ExitCodes.config,
      'pake.json already exists at ${file.path}; refusing to overwrite it.',
    );
  }

  const template = {
    'name': 'My App',
    'url': 'https://example.com',
    'bundleId': 'com.example.myapp',
    'version': '1.0.0',
    'buildNumber': 1,
    'injectScripts': <String>[],
    'permissions': <String>[],
  };

  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(template)}\n',
  );
}

class InitCommand extends Command<int> {
  InitCommand(this._output);

  final Output _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Generate a pake.json template in the current directory.';

  @override
  int run() {
    writeInitTemplate(Directory.current.path);
    _output.success({'created': p.join(Directory.current.path, 'pake.json')});
    return 0;
  }
}
```

- [ ] **Step 8: 实现 runner.dart 与 bin/pakem.dart**

`packages/pake_cli/lib/src/runner.dart`：

```dart
import 'package:args/command_runner.dart';

import 'commands/init.dart';
import 'output.dart';

/// 后续任务用 `addCommand` 往这里挂 build / doctor / icon。
CommandRunner<int> buildRunner(Output output) {
  return CommandRunner<int>('pakem', 'Build any web page into a mobile app.')
    ..addCommand(InitCommand(output));
}
```

`packages/pake_cli/bin/pakem.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/runner.dart';

Future<void> main(List<String> args) async {
  // --json 要在解析命令之前就知道，否则出错信息的格式会不一致。
  final json = args.contains('--json');
  final output = Output(json: json);

  try {
    final code = await buildRunner(output).run(args) ?? 0;
    exit(code);
  } on PakeException catch (e) {
    output.failure(e);
    exit(e.exitCode);
  } catch (e) {
    output.failure(PakeException(ExitCodes.build, e.toString()));
    exit(ExitCodes.build);
  }
}
```

- [ ] **Step 9: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test`
Expected: PASS，output 与 init 的测试全绿

- [ ] **Step 10: 手动验一次真实命令**

```bash
cd /tmp && rm -f pake.json
dart run /Users/hao/ai/pake_mobile/packages/pake_cli/bin/pakem.dart init
cat pake.json
```
Expected: 打印出缩进两格的模板 JSON

- [ ] **Step 11: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): add pakem skeleton with exit codes, json output and init"
```

---

### Task 5: 固定 workspace 与并发锁

**Files:**
- Create: `packages/pake_cli/lib/src/workspace.dart`
- Test: `packages/pake_cli/test/workspace_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `PakeException` / `ExitCodes`
- Produces:
  - `class Workspace { Workspace({String? root}); final String root; String get projectDir; String outDirFor(String appName); void ensureDirs(); T withLock<T>(T Function() action); }`
  - `root` 默认 `$HOME/.pake`，可注入以便测试用临时目录。

**为何必须有：** spec 里这是「一条命令快速出包」成立的前提。Flutter 增量缓存全在项目目录内（`.dart_tool/`、`build/`、`android/.gradle/`、`ios/Pods/`），每次复制到新临时目录等于每次冷构建。

**为何锁是「直接报错」而不是排队：** 排队会让 `--json` 的 agent 调用静默超时。报错更诚实，agent 能立刻看到 `exitCode: 2` 并决定重试还是放弃。

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/workspace_test.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Workspace ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_ws');
    ws = Workspace(root: tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('ensureDirs creates the workspace and out directories', () {
    ws.ensureDirs();

    expect(Directory(ws.projectDir).existsSync(), isTrue);
    expect(Directory('${tmp.path}/out').existsSync(), isTrue);
  });

  test('outDirFor sanitises app names into a safe directory segment', () {
    expect(ws.outDirFor('My App'), endsWith('/out/my-app'));
    expect(ws.outDirFor('Wei/Bo:2'), endsWith('/out/wei-bo-2'));
  });

  test('withLock runs the action and releases the lock afterwards', () {
    final result = ws.withLock(() => 'done');

    expect(result, 'done');
    expect(ws.withLock(() => 'again'), 'again',
        reason: 'a released lock must be re-acquirable');
  });

  test('withLock releases the lock even when the action throws', () {
    expect(() => ws.withLock(() => throw StateError('boom')), throwsStateError);

    expect(ws.withLock(() => 'recovered'), 'recovered');
  });

  test('a second holder fails immediately instead of queueing', () {
    ws.ensureDirs();
    File(ws.lockPath).writeAsStringSync('99999');

    expect(
      () => ws.withLock(() => 'never'),
      throwsA(isA<PakeException>()
          .having((e) => e.exitCode, 'exitCode', ExitCodes.environment)),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/workspace_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/workspace.dart'`

- [ ] **Step 3: 实现 workspace.dart**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'output.dart';

final _unsafeSegment = RegExp(r'[^a-z0-9]+');

/// 唯一的 Flutter 项目实例，Flutter / Gradle / CocoaPods 的增量缓存
/// 长期驻留其中。每次 build 只覆写会变的文件。
class Workspace {
  Workspace({String? root})
      : root = root ??
            p.join(
              Platform.environment['HOME'] ?? Directory.current.path,
              '.pake',
            );

  final String root;

  String get projectDir => p.join(root, 'workspace');

  String get lockPath => p.join(root, 'workspace.lock');

  String get logsDir => p.join(root, 'logs');

  String outDirFor(String appName) {
    final slug = appName
        .toLowerCase()
        .replaceAll(_unsafeSegment, '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return p.join(root, 'out', slug.isEmpty ? 'app' : slug);
  }

  void ensureDirs() {
    Directory(projectDir).createSync(recursive: true);
    Directory(p.join(root, 'out')).createSync(recursive: true);
    Directory(logsDir).createSync(recursive: true);
  }

  /// 单 workspace 不支持并行构建两个 app。
  ///
  /// 第二个进程**直接报错退出，不排队**——排队会让 `--json` 的 agent 调用
  /// 静默超时，报错更诚实。
  T withLock<T>(T Function() action) {
    ensureDirs();
    final lock = File(lockPath);

    if (lock.existsSync()) {
      throw PakeException(
        ExitCodes.environment,
        'Another pakem build holds ${lock.path} (pid '
        '${lock.readAsStringSync().trim()}). Wait for it to finish, or delete '
        'the lock file if that process is gone.',
      );
    }

    lock.writeAsStringSync('$pid');
    try {
      return action();
    } finally {
      if (lock.existsSync()) lock.deleteSync();
    }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/workspace_test.dart`
Expected: PASS，5 个测试全绿

- [ ] **Step 5: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): add fixed workspace with fail-fast build lock"
```

---

### Task 6: Android 物化（纯函数 + golden 比对）

**Files:**
- Create: `packages/pake_cli/lib/src/patch/android.dart`
- Test: `packages/pake_cli/test/patch/android_test.dart`
- Test: `packages/pake_cli/test/patch/fixtures/build.gradle.kts.in`
- Test: `packages/pake_cli/test/patch/fixtures/AndroidManifest.xml.in`

**Interfaces:**
- Consumes: Task 1 的 `PakeConfig` / `PakePermission`
- Produces:
  - `String patchBuildGradle(String original, PakeConfig config)`
  - `String patchAndroidManifest(String original, PakeConfig config)`

**为何是纯函数：** spec 的测试策略要求「给定 config → golden file 比对生成的 `AndroidManifest` / `Info.plist` / gradle 片段，**不跑真实构建**」。纯字符串函数让这条测试秒级完成，且覆盖了最易出错的字符串拼接。

- [ ] **Step 1: 准备 fixture**

`packages/pake_cli/test/patch/fixtures/build.gradle.kts.in`（`flutter create` 产出的相关片段，逐字复制）：

```kotlin
android {
    namespace = "com.example.pake_shell"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.example.pake_shell"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

`packages/pake_cli/test/patch/fixtures/AndroidManifest.xml.in`：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="pake_shell"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:windowSoftInputMode="adjustResize">
        </activity>
    </application>
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
```

- [ ] **Step 2: 写失败的测试**

`packages/pake_cli/test/patch/android_test.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/patch/android.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/patch/fixtures/$name').readAsStringSync();

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
  permissions: [PakePermission.camera, PakePermission.microphone],
);

void main() {
  group('patchBuildGradle', () {
    test('rewrites applicationId, namespace and version', () {
      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);

      expect(out, contains('applicationId = "com.pake.weibo"'));
      expect(out, contains('namespace = "com.pake.weibo"'));
      expect(out, contains('versionName = "2.1.0"'));
      expect(out, contains('versionCode = 42'));
      expect(out, isNot(contains('com.example.pake_shell')));
      expect(out, isNot(contains('flutter.versionCode')));
    });

    test('is idempotent — patching twice equals patching once', () {
      final once = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);
      expect(patchBuildGradle(once, _config), once);
    });

    test('leaves minSdk and targetSdk on the flutter defaults', () {
      final out = patchBuildGradle(_fixture('build.gradle.kts.in'), _config);

      expect(out, contains('minSdk = flutter.minSdkVersion'));
      expect(out, contains('targetSdk = flutter.targetSdkVersion'));
    });
  });

  group('patchAndroidManifest', () {
    test('rewrites the app label', () {
      final out =
          patchAndroidManifest(_fixture('AndroidManifest.xml.in'), _config);

      expect(out, contains('android:label="Weibo"'));
      expect(out, isNot(contains('android:label="pake_shell"')));
    });

    test('adds a uses-permission line for each declared permission', () {
      final out =
          patchAndroidManifest(_fixture('AndroidManifest.xml.in'), _config);

      expect(out, contains('android:name="android.permission.CAMERA"'));
      expect(out, contains('android:name="android.permission.RECORD_AUDIO"'));
      expect(out, isNot(contains('ACCESS_FINE_LOCATION')));
    });

    test('keeps INTERNET, which is never optional for a webview shell', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(permissions: []),
      );

      expect(out, contains('android.permission.INTERNET'));
    });

    test('does not duplicate permissions on a second patch', () {
      final once =
          patchAndroidManifest(_fixture('AndroidManifest.xml.in'), _config);
      final twice = patchAndroidManifest(once, _config);

      expect(twice, once);
      expect('android.permission.CAMERA'.allMatches(twice).length, 1);
    });

    test('removes a permission that is no longer declared', () {
      final withCamera =
          patchAndroidManifest(_fixture('AndroidManifest.xml.in'), _config);
      final withoutCamera =
          patchAndroidManifest(withCamera, _config.copyWith(permissions: []));

      expect(withoutCamera, isNot(contains('android.permission.CAMERA')));
      expect(withoutCamera, contains('android.permission.INTERNET'));
    });

    test('escapes XML-significant characters in the app name', () {
      final out = patchAndroidManifest(
        _fixture('AndroidManifest.xml.in'),
        _config.copyWith(name: 'Tom & Jerry "Show"'),
      );

      expect(out, contains('android:label="Tom &amp; Jerry &quot;Show&quot;"'));
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/patch/android_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/patch/android.dart'`

- [ ] **Step 4: 实现 android.dart**

关键设计：权限用一对标记注释围起来，重写时整块替换。这让「加权限」「删权限」「重复 patch」三种情况用同一段代码处理，也是上面幂等性测试能过的原因。

```dart
import 'package:pake_config/pake_config.dart';

const _permsBegin = '    <!-- pake:permissions:begin -->';
const _permsEnd = '    <!-- pake:permissions:end -->';

/// 把 CLI 管的字段写进 `android/app/build.gradle.kts`。
///
/// minSdk / targetSdk 保持 flutter 默认——那是 Flutter 工具链的事，
/// pake 不该越界。
String patchBuildGradle(String original, PakeConfig config) {
  return original
      .replaceAll(
        RegExp(r'namespace\s*=\s*"[^"]*"'),
        'namespace = "${config.bundleId}"',
      )
      .replaceAll(
        RegExp(r'applicationId\s*=\s*"[^"]*"'),
        'applicationId = "${config.bundleId}"',
      )
      .replaceAll(
        RegExp(r'versionCode\s*=\s*[^\n]+'),
        'versionCode = ${config.buildNumber}',
      )
      .replaceAll(
        RegExp(r'versionName\s*=\s*[^\n]+'),
        'versionName = "${config.version}"',
      );
}

/// 把 app 名与权限声明写进 `android/app/src/main/AndroidManifest.xml`。
String patchAndroidManifest(String original, PakeConfig config) {
  var out = original.replaceAll(
    RegExp(r'android:label="[^"]*"'),
    'android:label="${_escapeXmlAttribute(config.name)}"',
  );

  final block = [
    _permsBegin,
    for (final p in config.permissions)
      '    <uses-permission android:name="${p.androidPermission}"/>',
    _permsEnd,
  ].join('\n');

  final existing = RegExp(
    '${RegExp.escape(_permsBegin)}.*?${RegExp.escape(_permsEnd)}',
    dotAll: true,
  );

  if (existing.hasMatch(out)) {
    return out.replaceFirst(existing, block);
  }

  // 首次 patch：插在 </manifest> 之前。
  return out.replaceFirst('</manifest>', '$block\n</manifest>');
}

String _escapeXmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/patch/android_test.dart`
Expected: PASS，9 个测试全绿

- [ ] **Step 6: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): materialize android gradle and manifest as pure functions"
```

---

### Task 7: iOS 物化 + ExportOptions.plist

**Files:**
- Create: `packages/pake_cli/lib/src/patch/ios.dart`
- Test: `packages/pake_cli/test/patch/ios_test.dart`
- Test: `packages/pake_cli/test/patch/fixtures/Info.plist.in`

**Interfaces:**
- Consumes: Task 1 的 `PakeConfig` / `PakePermission`
- Produces:
  - `String patchInfoPlist(String original, PakeConfig config)`
  - `String patchPbxproj(String original, PakeConfig config)`
  - `String exportOptionsPlist({required String teamId, required String profileName, required String bundleId, String method = 'development'})`

- [ ] **Step 1: 准备 fixture**

`packages/pake_cli/test/patch/fixtures/Info.plist.in`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Pake Shell</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
</dict>
</plist>
```

- [ ] **Step 2: 写失败的测试**

`packages/pake_cli/test/patch/ios_test.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/patch/ios.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/patch/fixtures/$name').readAsStringSync();

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
  permissions: [PakePermission.location],
);

void main() {
  group('patchInfoPlist', () {
    test('rewrites the display name', () {
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(out, contains('''
	<key>CFBundleDisplayName</key>
	<string>Weibo</string>'''));
    });

    test('leaves version keys on the xcode build variables', () {
      // 版本号经 `flutter build --build-name/--build-number` 传入，
      // 直接改 plist 反而会和 Flutter 工具链打架。
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(out, contains(r'$(FLUTTER_BUILD_NAME)'));
      expect(out, contains(r'$(FLUTTER_BUILD_NUMBER)'));
    });

    test('adds a usage-description key for each declared permission', () {
      final out = patchInfoPlist(_fixture('Info.plist.in'), _config);

      expect(out, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
      expect(out, isNot(contains('NSCameraUsageDescription')));
    });

    test('is idempotent', () {
      final once = patchInfoPlist(_fixture('Info.plist.in'), _config);
      expect(patchInfoPlist(once, _config), once);
    });

    test('removes a usage description that is no longer declared', () {
      final withLocation = patchInfoPlist(_fixture('Info.plist.in'), _config);
      final without =
          patchInfoPlist(withLocation, _config.copyWith(permissions: []));

      expect(without, isNot(contains('NSLocationWhenInUseUsageDescription')));
      expect(without, contains('<key>UILaunchStoryboardName</key>'));
    });

    test('escapes XML-significant characters in the display name', () {
      final out = patchInfoPlist(
        _fixture('Info.plist.in'),
        _config.copyWith(name: 'Tom & Jerry'),
      );

      expect(out, contains('<string>Tom &amp; Jerry</string>'));
    });
  });

  group('patchPbxproj', () {
    test('rewrites every PRODUCT_BUNDLE_IDENTIFIER occurrence', () {
      const original = '''
				PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell.RunnerTests;
''';

      final out = patchPbxproj(original, _config);

      expect(out, contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo;'));
      expect(
        out,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo.RunnerTests;'),
        reason: 'the test target suffix must be preserved',
      );
    });
  });

  group('exportOptionsPlist', () {
    test('embeds team id, method and the profile mapping', () {
      final out = exportOptionsPlist(
        teamId: 'ABCDE12345',
        profileName: 'Pake Dev Profile',
        bundleId: 'com.pake.weibo',
      );

      expect(out, contains('<key>teamID</key>'));
      expect(out, contains('<string>ABCDE12345</string>'));
      expect(out, contains('<string>development</string>'));
      expect(out, contains('<key>com.pake.weibo</key>'));
      expect(out, contains('<string>Pake Dev Profile</string>'));
    });

    test('honours a non-default export method', () {
      final out = exportOptionsPlist(
        teamId: 'ABCDE12345',
        profileName: 'Pake AdHoc',
        bundleId: 'com.pake.weibo',
        method: 'ad-hoc',
      );

      expect(out, contains('<string>ad-hoc</string>'));
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/patch/ios_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/patch/ios.dart'`

- [ ] **Step 4: 实现 ios.dart**

```dart
import 'package:pake_config/pake_config.dart';

const _permsBegin = '\t<!-- pake:permissions:begin -->';
const _permsEnd = '\t<!-- pake:permissions:end -->';

/// 把 app 名与权限用途说明写进 `ios/Runner/Info.plist`。
///
/// 版本号**不动**——它由 `flutter build --build-name/--build-number` 经
/// `$(FLUTTER_BUILD_NAME)` 变量注入，直接改 plist 会和工具链打架。
String patchInfoPlist(String original, PakeConfig config) {
  var out = original.replaceFirst(
    RegExp(
      r'(<key>CFBundleDisplayName</key>\s*\n\s*<string>)[^<]*(</string>)',
    ),
    '\${1}${_escapeXmlText(config.name)}\${2}',
  );

  final block = [
    _permsBegin,
    for (final p in config.permissions) ...[
      '\t<key>${p.iosUsageKey}</key>',
      '\t<string>${_escapeXmlText(p.iosUsageDescription)}</string>',
    ],
    _permsEnd,
  ].join('\n');

  final existing = RegExp(
    '${RegExp.escape(_permsBegin)}.*?${RegExp.escape(_permsEnd)}',
    dotAll: true,
  );

  if (existing.hasMatch(out)) {
    return out.replaceFirst(existing, block);
  }

  return out.replaceFirst('</dict>', '$block\n</dict>');
}

/// 改 `ios/Runner.xcodeproj/project.pbxproj` 里的 bundle id。
///
/// 用 `replaceAllMapped` 保留 `.RunnerTests` 这类后缀——直接整行替换会
/// 把 test target 的 id 也压成主 target 的，导致签名冲突。
String patchPbxproj(String original, PakeConfig config) {
  return original.replaceAllMapped(
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+?)(\.RunnerTests)?;'),
    (m) => 'PRODUCT_BUNDLE_IDENTIFIER = ${config.bundleId}${m[2] ?? ''};',
  );
}

/// 生成 `flutter build ipa --export-options-plist` 要的文件。
String exportOptionsPlist({
  required String teamId,
  required String profileName,
  required String bundleId,
  String method = 'development',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>$method</string>
	<key>teamID</key>
	<string>$teamId</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>provisioningProfiles</key>
	<dict>
		<key>$bundleId</key>
		<string>$profileName</string>
	</dict>
</dict>
</plist>
''';
}

String _escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/patch/ios_test.dart`
Expected: PASS，9 个测试全绿

- [ ] **Step 6: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): materialize Info.plist, pbxproj and ExportOptions.plist"
```

---

### Task 8: 注入脚本物化（自动包 try/catch）

**Files:**
- Create: `packages/pake_cli/lib/src/patch/scripts.dart`
- Test: `packages/pake_cli/test/patch/scripts_test.dart`

**Interfaces:**
- Consumes: 无（纯字符串处理）
- Produces:
  - `class MaterializedScript { const MaterializedScript({required this.id, required this.kind, required this.source}); final String id; final ScriptKind kind; final String source; }`
  - `enum ScriptKind { js, css }`
  - `MaterializedScript materializeScript({required String path, required String content})`

**为何必须包 try/catch：** spec 明确要求「单个脚本抛异常不得导致整页失效」。`UserScript` 是按顺序注入的，一个脚本在 `atDocumentStart` 抛异常会中断后续注入。

**CSS 也要处理：** spec 说注入 `scripts/*.js` 与 `*.css`。CSS 不能直接当 `UserScript.source`，得包成一段插 `<style>` 的 JS。

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/patch/scripts_test.dart`：

```dart
import 'package:pake_cli/src/patch/scripts.dart';
import 'package:test/test.dart';

void main() {
  group('materializeScript', () {
    test('derives a stable id from the file name', () {
      final s = materializeScript(
        path: 'scripts/remove-ads.js',
        content: 'console.log(1);',
      );

      expect(s.id, 'remove-ads');
      expect(s.kind, ScriptKind.js);
    });

    test('wraps js in a try/catch so one bad script cannot kill the page', () {
      final s = materializeScript(
        path: 'a.js',
        content: 'throw new Error("boom");',
      );

      expect(s.source, contains('try {'));
      expect(s.source, contains('throw new Error("boom");'));
      expect(s.source, contains('catch'));
      expect(s.source, contains('console.error'),
          reason: 'errors must reach onConsoleMessage to land in the log');
      expect(s.source, contains('[pake:a]'),
          reason: 'the log line must name the offending script');
    });

    test('turns css into a style-injecting script', () {
      final s = materializeScript(
        path: 'theme.css',
        content: 'body { background: red; }',
      );

      expect(s.kind, ScriptKind.css);
      expect(s.source, contains('createElement'));
      expect(s.source, contains('body { background: red; }'));
      expect(s.source, contains('try {'));
    });

    test('escapes backticks and \${ so css cannot break out of the template', () {
      final s = materializeScript(
        path: 'evil.css',
        content: r'body::after { content: "`${alert(1)}`"; }',
      );

      expect(s.source, contains(r'\`'));
      expect(s.source, contains(r'\${'));
    });

    test('rejects an unsupported extension', () {
      expect(
        () => materializeScript(path: 'thing.txt', content: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('id survives a path with directories and dots', () {
      final s = materializeScript(
        path: '/tmp/my.stuff/fix-video.min.js',
        content: '',
      );

      expect(s.id, 'fix-video.min');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/patch/scripts_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/patch/scripts.dart'`

- [ ] **Step 3: 实现 scripts.dart**

```dart
import 'package:path/path.dart' as p;

enum ScriptKind { js, css }

/// 一个已物化的注入脚本：`id` 是运行期开关的键，`source` 是最终注入
/// WebView 的 JS 文本（CSS 已被包成插 `<style>` 的 JS）。
class MaterializedScript {
  const MaterializedScript({
    required this.id,
    required this.kind,
    required this.source,
  });

  final String id;
  final ScriptKind kind;
  final String source;

  Map<String, Object?> toJson() =>
      {'id': id, 'kind': kind.name, 'source': source};
}

/// 把源文件变成可直接注入的 JS。
///
/// 一律包 try/catch —— spec 要求单个脚本抛异常不得导致整页失效，
/// 而 `UserScript` 是顺序注入的，一个异常会中断后面的脚本。
MaterializedScript materializeScript({
  required String path,
  required String content,
}) {
  final ext = p.extension(path).toLowerCase();
  final id = p.basenameWithoutExtension(path);

  final kind = switch (ext) {
    '.js' => ScriptKind.js,
    '.css' => ScriptKind.css,
    _ => throw ArgumentError.value(
        path,
        'path',
        'Only .js and .css can be injected',
      ),
  };

  final body = switch (kind) {
    ScriptKind.js => content,
    ScriptKind.css => '''
  var style = document.createElement('style');
  style.type = 'text/css';
  style.appendChild(document.createTextNode(`${_escapeTemplate(content)}`));
  (document.head || document.documentElement).appendChild(style);''',
  };

  return MaterializedScript(
    id: id,
    kind: kind,
    source: '''
(function () {
try {
$body
} catch (e) {
  console.error('[pake:$id]', e && e.message ? e.message : e);
}
})();
''',
  );
}

/// CSS 内容嵌进 JS 模板字符串，必须转义反引号与 `\${`，
/// 否则恶意或手滑的 CSS 能逃出模板执行任意代码。
String _escapeTemplate(String css) =>
    css.replaceAll(r'\', r'\\').replaceAll('`', r'\`').replaceAll(r'${', r'\${');
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/patch/scripts_test.dart`
Expected: PASS，6 个测试全绿

- [ ] **Step 5: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): materialize inject scripts with per-script try/catch"
```

---

### Task 9: `pakem build` —— 把流水线串起来

**Files:**
- Create: `packages/pake_cli/lib/src/process_runner.dart`
- Create: `packages/pake_cli/lib/src/build_pipeline.dart`
- Create: `packages/pake_cli/lib/src/commands/build.dart`
- Modify: `packages/pake_cli/lib/src/runner.dart`（挂上 BuildCommand）
- Test: `packages/pake_cli/test/build_pipeline_test.dart`

**Interfaces:**
- Consumes: Task 2 `validateConfig` · Task 3 `mergeConfig` / `PakeFlags` · Task 4 `Output` / `PakeException` / `ExitCodes` · Task 5 `Workspace` · Task 6 `patchBuildGradle` / `patchAndroidManifest` · Task 7 `patchInfoPlist` / `patchPbxproj` / `exportOptionsPlist` · Task 8 `materializeScript`
- Produces:
  - `abstract class ProcessRunner { Future<ProcessResult> run(String executable, List<String> args, {String? workingDirectory}); }`
  - `class RealProcessRunner implements ProcessRunner`
  - `enum PakePlatform { android, ios }`
  - `Map<String, Object?> loadConfigJson({String? explicitPath, required String cwd})` —— 实现 spec 的三级查找顺序
  - `List<String> flutterBuildArgs(PakePlatform platform, PakeConfig config, {String? exportOptionsPath})`
  - `Future<List<String>> runBuild({required PakeConfig config, required List<PakePlatform> platforms, required Workspace workspace, required ProcessRunner runner, required Output output, String? exportOptionsPath})`

**为何 `ProcessRunner` 要抽象：** spec 的测试策略明确「不跑真实构建」。注入 fake runner 后，「build 命令是否用正确参数调了 flutter」这件最易错的事变成秒级单测。

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/build_pipeline_test.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/build_pipeline.dart';
import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.exitCode = 0});

  final int exitCode;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return ProcessResult(0, exitCode, 'stdout', 'stderr');
  }
}

const _config = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  version: '2.1.0',
  buildNumber: 42,
);

void main() {
  group('loadConfigJson', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_cfg'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('prefers an explicit --config path over the cwd file', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{"name":"cwd"}');
      File('${tmp.path}/other.json').writeAsStringSync('{"name":"explicit"}');

      final json = loadConfigJson(
        explicitPath: '${tmp.path}/other.json',
        cwd: tmp.path,
      );

      expect(json['name'], 'explicit');
    });

    test('falls back to pake.json in the cwd', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{"name":"cwd"}');

      expect(loadConfigJson(cwd: tmp.path)['name'], 'cwd');
    });

    test('returns empty when no config file exists', () {
      expect(loadConfigJson(cwd: tmp.path), isEmpty);
    });

    test('errors with exit code 1 when --config points at a missing file', () {
      expect(
        () => loadConfigJson(explicitPath: '${tmp.path}/nope.json', cwd: tmp.path),
        throwsA(isA<PakeException>()
            .having((e) => e.exitCode, 'exitCode', ExitCodes.config)),
      );
    });

    test('errors with exit code 1 on malformed json', () {
      File('${tmp.path}/pake.json').writeAsStringSync('{not json');

      expect(
        () => loadConfigJson(cwd: tmp.path),
        throwsA(isA<PakeException>()
            .having((e) => e.exitCode, 'exitCode', ExitCodes.config)),
      );
    });
  });

  group('flutterBuildArgs', () {
    test('android splits per abi and passes version through', () {
      final args = flutterBuildArgs(PakePlatform.android, _config);

      expect(args, containsAllInOrder(['build', 'apk']));
      expect(args, contains('--release'));
      expect(args, contains('--split-per-abi'));
      expect(args, contains('--build-name=2.1.0'));
      expect(args, contains('--build-number=42'));
    });

    test('ios passes the export options plist', () {
      final args = flutterBuildArgs(
        PakePlatform.ios,
        _config,
        exportOptionsPath: '/tmp/ExportOptions.plist',
      );

      expect(args, containsAllInOrder(['build', 'ipa']));
      expect(args, contains('--export-options-plist=/tmp/ExportOptions.plist'));
      expect(args, isNot(contains('--split-per-abi')));
    });
  });

  group('runBuild', () {
    late Directory tmp;
    late Workspace ws;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pakem_build');
      ws = Workspace(root: tmp.path)..ensureDirs();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('invokes flutter build once per requested platform', () async {
      final runner = _FakeRunner();

      await runBuild(
        config: _config,
        platforms: [PakePlatform.android],
        workspace: ws,
        runner: runner,
        output: Output(json: true, sink: StringBuffer()),
      );

      expect(runner.calls.length, 1);
      expect(runner.calls.single.first, 'flutter');
      expect(runner.calls.single, contains('apk'));
    });

    test('throws exit code 3 when flutter build fails', () async {
      final runner = _FakeRunner(exitCode: 1);

      expect(
        () => runBuild(
          config: _config,
          platforms: [PakePlatform.android],
          workspace: ws,
          runner: runner,
          output: Output(json: true, sink: StringBuffer()),
        ),
        throwsA(isA<PakeException>()
            .having((e) => e.exitCode, 'exitCode', ExitCodes.build)),
      );
    });

    test('writes the full build log to the workspace logs dir on failure', () async {
      final runner = _FakeRunner(exitCode: 1);

      try {
        await runBuild(
          config: _config,
          platforms: [PakePlatform.android],
          workspace: ws,
          runner: runner,
          output: Output(json: true, sink: StringBuffer()),
        );
      } on PakeException catch (e) {
        expect(e.message, contains(ws.logsDir),
            reason: 'the terminal must point at the log, per spec');
      }

      final logs = Directory(ws.logsDir).listSync();
      expect(logs, isNotEmpty);
      expect(File(logs.first.path).readAsStringSync(), contains('stderr'));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/build_pipeline_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/build_pipeline.dart'`

- [ ] **Step 3: 实现 process_runner.dart**

```dart
import 'dart:io';

/// 抽象出来是为了让 build 流水线的测试不真的跑 flutter——
/// spec 的测试策略明确要求「不跑真实构建」。
abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  });
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) =>
      Process.run(executable, args, workingDirectory: workingDirectory);
}
```

- [ ] **Step 4: 实现 build_pipeline.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import 'output.dart';
import 'process_runner.dart';
import 'workspace.dart';

enum PakePlatform {
  android,
  ios;

  static PakePlatform byName(String name) {
    for (final v in PakePlatform.values) {
      if (v.name == name) return v;
    }
    throw PakeException(
      ExitCodes.config,
      'Unknown platform "$name"; expected android or ios.',
    );
  }
}

/// spec 的查找顺序：`--config` > cwd 的 `pake.json` > 无文件。
/// 三者**不叠加**，取第一个命中的来源。
Map<String, Object?> loadConfigJson({String? explicitPath, required String cwd}) {
  final File file;
  if (explicitPath != null) {
    file = File(explicitPath);
    if (!file.existsSync()) {
      throw PakeException(
        ExitCodes.config,
        'Config file not found: $explicitPath',
      );
    }
  } else {
    file = File(p.join(cwd, 'pake.json'));
    if (!file.existsSync()) return const {};
  }

  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    throw PakeException(
      ExitCodes.config,
      'Could not parse ${file.path} as JSON: $e',
    );
  }
}

List<String> flutterBuildArgs(
  PakePlatform platform,
  PakeConfig config, {
  String? exportOptionsPath,
}) {
  final common = [
    '--release',
    '--build-name=${config.version}',
    '--build-number=${config.buildNumber}',
  ];

  return switch (platform) {
    PakePlatform.android => ['build', 'apk', ...common, '--split-per-abi'],
    PakePlatform.ios => [
        'build',
        'ipa',
        ...common,
        if (exportOptionsPath != null)
          '--export-options-plist=$exportOptionsPath',
      ],
  };
}

/// 逐个平台调 `flutter build`，返回产物路径。
///
/// 失败时全量输出落 `~/.pake/logs/`，终端只给关键行 + 日志路径——
/// gradle 那几千行刷屏对定位问题毫无帮助。
Future<List<String>> runBuild({
  required PakeConfig config,
  required List<PakePlatform> platforms,
  required Workspace workspace,
  required ProcessRunner runner,
  required Output output,
  String? exportOptionsPath,
}) async {
  final artifacts = <String>[];

  for (final platform in platforms) {
    output.info('Building ${platform.name}…');

    final args = flutterBuildArgs(
      platform,
      config,
      exportOptionsPath: exportOptionsPath,
    );
    final result = await runner.run(
      'flutter',
      args,
      workingDirectory: workspace.projectDir,
    );

    if (result.exitCode != 0) {
      final logPath = _writeBuildLog(workspace, platform, args, result);
      throw PakeException(
        ExitCodes.build,
        'flutter ${args.join(' ')} failed with exit code ${result.exitCode}.\n'
        '${_lastLines(result.stderr.toString(), 10)}\n'
        'Full output: $logPath',
      );
    }

    artifacts.addAll(_collectArtifacts(workspace, platform));
  }

  return artifacts;
}

String _writeBuildLog(
  Workspace workspace,
  PakePlatform platform,
  List<String> args,
  ProcessResult result,
) {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final path = p.join(workspace.logsDir, 'build-${platform.name}-$stamp.log');
  File(path).writeAsStringSync('''
\$ flutter ${args.join(' ')}
exit code: ${result.exitCode}

--- stdout ---
${result.stdout}

--- stderr ---
${result.stderr}
''');
  return path;
}

String _lastLines(String text, int count) {
  final lines = text.trimRight().split('\n');
  return lines.sublist(lines.length > count ? lines.length - count : 0).join('\n');
}

List<String> _collectArtifacts(Workspace workspace, PakePlatform platform) {
  final dir = switch (platform) {
    PakePlatform.android =>
      Directory(p.join(workspace.projectDir, 'build/app/outputs/flutter-apk')),
    PakePlatform.ios =>
      Directory(p.join(workspace.projectDir, 'build/ios/ipa')),
  };

  if (!dir.existsSync()) return const [];

  final wanted = platform == PakePlatform.android ? '.apk' : '.ipa';
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((path) => path.endsWith(wanted))
      .toList()
    ..sort();
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/build_pipeline_test.dart`
Expected: PASS，10 个测试全绿

- [ ] **Step 6: 实现 build.dart 命令层**

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pake_config/pake_config.dart';

import '../build_pipeline.dart';
import '../output.dart';
import '../process_runner.dart';
import '../workspace.dart';

class BuildCommand extends Command<int> {
  BuildCommand(this._output, {ProcessRunner? runner, Workspace? workspace})
      : _runner = runner ?? const RealProcessRunner(),
        _workspace = workspace ?? Workspace() {
    argParser
      // 默认 android：iOS 需要签名参数，静默尝试双端后失败会让首次
      // 使用者困惑。要 iOS 就显式写出来。
      ..addOption('platform', defaultsTo: 'android')
      ..addOption('config')
      ..addOption('name')
      ..addOption('icon')
      ..addOption('bundle-id')
      ..addOption('version')
      ..addOption('team-id')
      ..addOption('profile')
      ..addMultiOption('inject')
      ..addFlag('json', negatable: false);
  }

  final Output _output;
  final ProcessRunner _runner;
  final Workspace _workspace;

  @override
  String get name => 'build';

  @override
  String get description => 'Build the given URL into an app.';

  @override
  String get invocation => 'pakem build <url> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final url = args.rest.isEmpty ? null : args.rest.first;

    final config = mergeConfig(
      fileJson: loadConfigJson(
        explicitPath: args.option('config'),
        cwd: Directory.current.path,
      ),
      flags: PakeFlags(
        name: args.option('name'),
        url: url,
        bundleId: args.option('bundle-id'),
        version: args.option('version'),
        iconPath: args.option('icon'),
        injectScripts:
            args.wasParsed('inject') ? args.multiOption('inject') : null,
      ),
    );

    final errors = validateConfig(config);
    if (errors.isNotEmpty) {
      throw PakeException(
        ExitCodes.config,
        'Invalid configuration (${errors.length} problem(s)).',
        details: errors,
      );
    }

    final platforms = args
        .option('platform')!
        .split(',')
        .map((s) => PakePlatform.byName(s.trim()))
        .toList();

    final artifacts = await _workspace.withLock(() async {
      // Task 10 会在这里插入 workspace 同步 + 物化；
      // 现在先直接构建，好让这一步独立可测。
      return runBuild(
        config: config,
        platforms: platforms,
        workspace: _workspace,
        runner: _runner,
        output: _output,
      );
    });

    _output.success({'app': config.name, 'artifacts': artifacts});
    return 0;
  }
}
```

> **注意 `withLock` 的类型**：Task 5 的 `withLock<T>` 是同步的，这里传的是 `Future<List<String>> Function()`，`T` 推导为 `Future<List<String>>`，`finally` 会在 Future **创建后**立刻释放锁而非完成后。**必须在本步同时把 `Workspace.withLock` 改成 `Future<T> withLock<T>(Future<T> Function() action) async`**，并把 Task 5 的测试同步改成 `await`。这是计划里唯一一处需要回改早前任务的地方。

- [ ] **Step 7: 挂到 runner 并跑全量测试**

在 `runner.dart` 加 `..addCommand(BuildCommand(output))`。

Run: `cd packages/pake_cli && dart test`
Expected: PASS（workspace_test 已改为 async）

- [ ] **Step 8: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): add build command with injectable process runner"
```

---

### Task 10: workspace 同步与物化落盘

**Files:**
- Create: `packages/pake_cli/lib/src/materialize.dart`
- Modify: `packages/pake_cli/lib/src/commands/build.dart`（在 `withLock` 里插入同步与物化）
- Test: `packages/pake_cli/test/materialize_test.dart`

**Interfaces:**
- Consumes: Task 5 `Workspace` · Task 6 `patchBuildGradle` / `patchAndroidManifest` · Task 7 `patchInfoPlist` / `patchPbxproj` · Task 8 `materializeScript`
- Produces:
  - `void syncTemplate({required String templateDir, required String projectDir})` —— 幂等复制模板，**跳过缓存目录**
  - `void materializeConfig({required PakeConfig config, required Workspace workspace, required String cwd})`

**这一步是「固定 workspace」设计的落点。** 同步必须跳过 `.dart_tool/`、`build/`、`android/.gradle/`、`ios/Pods/`、`.git/` —— 复制或删除这些等于自毁增量缓存，整个固定 workspace 的意义就没了。

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/materialize_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/src/materialize.dart';
import 'package:pake_cli/src/workspace.dart';
import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void _write(String path, String content) =>
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  late Directory tmp;
  late String templateDir;
  late Workspace ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pakem_mat');
    templateDir = '${tmp.path}/template';
    ws = Workspace(root: '${tmp.path}/pake')..ensureDirs();

    _write('$templateDir/lib/main.dart', 'void main() {}');
    _write('$templateDir/android/app/build.gradle.kts',
        'android { applicationId = "com.example.pake_shell" }');
    _write('$templateDir/android/app/src/main/AndroidManifest.xml',
        '<manifest><application android:label="pake_shell"/></manifest>');
    _write('$templateDir/ios/Runner/Info.plist', '''
<plist><dict>
	<key>CFBundleDisplayName</key>
	<string>Pake Shell</string>
</dict></plist>''');
    _write('$templateDir/ios/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.pakeShell;');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('syncTemplate', () {
    test('copies template files into the project dir', () {
      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(File('${ws.projectDir}/lib/main.dart').existsSync(), isTrue);
    });

    test('never touches incremental cache directories', () {
      // 模拟上一次构建留下的缓存。
      _write('${ws.projectDir}/.dart_tool/version', 'cached');
      _write('${ws.projectDir}/build/app/stale.apk', 'cached');
      _write('${ws.projectDir}/android/.gradle/lock', 'cached');
      _write('${ws.projectDir}/ios/Pods/Manifest.lock', 'cached');
      // 模板里也放一份同名文件，确认它不会被复制过来。
      _write('$templateDir/.dart_tool/version', 'from-template');

      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(File('${ws.projectDir}/.dart_tool/version').readAsStringSync(),
          'cached', reason: 'losing this means every build is a cold build');
      expect(File('${ws.projectDir}/build/app/stale.apk').existsSync(), isTrue);
      expect(File('${ws.projectDir}/android/.gradle/lock').existsSync(), isTrue);
      expect(File('${ws.projectDir}/ios/Pods/Manifest.lock').existsSync(), isTrue);
    });

    test('overwrites a template file that changed', () {
      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);
      _write('$templateDir/lib/main.dart', 'void main() { print(1); }');

      syncTemplate(templateDir: templateDir, projectDir: ws.projectDir);

      expect(File('${ws.projectDir}/lib/main.dart').readAsStringSync(),
          contains('print(1)'));
    });
  });

  group('materializeConfig', () {
    const config = PakeConfig(
      name: 'Weibo',
      url: 'https://m.weibo.cn',
      bundleId: 'com.pake.weibo',
      version: '2.1.0',
      buildNumber: 42,
    );

    setUp(() => syncTemplate(templateDir: templateDir, projectDir: ws.projectDir));

    test('writes assets/pake.json that the shell can read back', () {
      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      final raw =
          File('${ws.projectDir}/assets/pake.json').readAsStringSync();
      final restored =
          PakeConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);

      expect(restored.url, 'https://m.weibo.cn');
      expect(restored.name, 'Weibo');
    });

    test('patches gradle, manifest, plist and pbxproj', () {
      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      expect(
        File('${ws.projectDir}/android/app/build.gradle.kts').readAsStringSync(),
        contains('com.pake.weibo'),
      );
      expect(
        File('${ws.projectDir}/android/app/src/main/AndroidManifest.xml')
            .readAsStringSync(),
        contains('android:label="Weibo"'),
      );
      expect(
        File('${ws.projectDir}/ios/Runner/Info.plist').readAsStringSync(),
        contains('<string>Weibo</string>'),
      );
      expect(
        File('${ws.projectDir}/ios/Runner.xcodeproj/project.pbxproj')
            .readAsStringSync(),
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.pake.weibo;'),
      );
    });

    test('writes each inject script wrapped in try/catch', () {
      _write('${tmp.path}/hide-ads.js', 'document.body.remove();');

      materializeConfig(
        config: config.copyWith(injectScripts: ['${tmp.path}/hide-ads.js']),
        workspace: ws,
        cwd: tmp.path,
      );

      final out = File('${ws.projectDir}/assets/scripts/hide-ads.js')
          .readAsStringSync();
      expect(out, contains('try {'));
      expect(out, contains('document.body.remove();'));

      final manifest = jsonDecode(
        File('${ws.projectDir}/assets/scripts/index.json').readAsStringSync(),
      ) as List<Object?>;
      expect(manifest.length, 1);
      expect((manifest.first! as Map)['id'], 'hide-ads');
    });

    test('drops scripts left over from a previous build', () {
      _write('${ws.projectDir}/assets/scripts/old.js', 'stale');
      _write('${ws.projectDir}/assets/scripts/index.json', '[{"id":"old"}]');

      materializeConfig(config: config, workspace: ws, cwd: tmp.path);

      expect(
        File('${ws.projectDir}/assets/scripts/old.js').existsSync(),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/materialize_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/materialize.dart'`

- [ ] **Step 3: 实现 materialize.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import 'output.dart';
import 'patch/android.dart';
import 'patch/ios.dart';
import 'patch/scripts.dart';
import 'workspace.dart';

/// 增量缓存所在，同步时必须绕开。
///
/// 复制或删除它们等于每次冷构建——Android 数分钟、iOS 更久，
/// 「一条命令快速出包」就不成立了。
const _cacheDirs = {
  '.dart_tool',
  'build',
  '.gradle',
  'Pods',
  '.git',
  '.symlinks',
};

/// 幂等地把模板同步进固定 workspace：只覆写会变的文件，其余不动。
void syncTemplate({required String templateDir, required String projectDir}) {
  final template = Directory(templateDir);
  for (final entity in template.listSync(recursive: true)) {
    if (entity is! File) continue;

    final relative = p.relative(entity.path, from: templateDir);
    if (p.split(relative).any(_cacheDirs.contains)) continue;

    final target = File(p.join(projectDir, relative));
    target.parent.createSync(recursive: true);

    // 内容相同就别写——无谓的 mtime 变化会让 Gradle 判定任务失效。
    if (target.existsSync() &&
        target.readAsBytesSync().length == entity.lengthSync() &&
        target.readAsStringSync() == entity.readAsStringSync()) {
      continue;
    }
    entity.copySync(target.path);
  }
}

/// 把配置物化进已同步的 workspace。
void materializeConfig({
  required PakeConfig config,
  required Workspace workspace,
  required String cwd,
}) {
  final root = workspace.projectDir;

  _patchFile(p.join(root, 'android/app/build.gradle.kts'),
      (s) => patchBuildGradle(s, config));
  _patchFile(p.join(root, 'android/app/src/main/AndroidManifest.xml'),
      (s) => patchAndroidManifest(s, config));
  _patchFile(
      p.join(root, 'ios/Runner/Info.plist'), (s) => patchInfoPlist(s, config));
  _patchFile(p.join(root, 'ios/Runner.xcodeproj/project.pbxproj'),
      (s) => patchPbxproj(s, config));

  // 壳在启动时读它作为运行期默认值。
  final assetsDir = Directory(p.join(root, 'assets'))..createSync(recursive: true);
  File(p.join(assetsDir.path, 'pake.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );

  _materializeScripts(config: config, root: root, cwd: cwd);
}

void _materializeScripts({
  required PakeConfig config,
  required String root,
  required String cwd,
}) {
  final dir = Directory(p.join(root, 'assets/scripts'));
  // 先清空：上一次构建的脚本若留在这里，会被 UserScript 一并注入。
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  final manifest = <Map<String, Object?>>[];
  for (final rawPath in config.injectScripts) {
    final source = File(p.isAbsolute(rawPath) ? rawPath : p.join(cwd, rawPath));
    if (!source.existsSync()) {
      throw PakeException(
        ExitCodes.config,
        'Inject file not found: ${source.path}',
      );
    }

    final script = materializeScript(
      path: source.path,
      content: source.readAsStringSync(),
    );
    File(p.join(dir.path, '${script.id}.js'))
        .writeAsStringSync(script.source);
    manifest.add({'id': script.id, 'kind': script.kind.name});
  }

  File(p.join(dir.path, 'index.json'))
      .writeAsStringSync(jsonEncode(manifest));
}

void _patchFile(String path, String Function(String) patch) {
  final file = File(path);
  if (!file.existsSync()) return;
  final patched = patch(file.readAsStringSync());
  // 内容没变就不写，保住 Gradle 的 up-to-date 判定。
  if (file.readAsStringSync() == patched) return;
  file.writeAsStringSync(patched);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/materialize_test.dart`
Expected: PASS，7 个测试全绿

- [ ] **Step 5: 接进 build 命令**

在 `BuildCommand.run` 的 `withLock` 回调里，`runBuild` 之前插入：

```dart
      syncTemplate(
        templateDir: _templateDir,
        projectDir: _workspace.projectDir,
      );
      materializeConfig(
        config: config,
        workspace: _workspace,
        cwd: Directory.current.path,
      );
```

`_templateDir` 解析为 `pake_shell` 包的路径。构造函数加可选参数 `String? templateDir`，默认从 `Platform.script` 上溯定位 `packages/pake_shell`：

```dart
  String get _templateDir =>
      _templateDirOverride ??
      p.normalize(p.join(
        p.dirname(Platform.script.toFilePath()),
        '../../pake_shell',
      ));
```

- [ ] **Step 6: 跑全量测试并提交**

Run: `cd packages/pake_cli && dart test`
Expected: PASS

```bash
git add packages/pake_cli
git commit -m "feat(cli): sync template and materialize config into fixed workspace"
```

---

### Task 11: `pakem doctor` 与 iOS 签名前置检查

**Files:**
- Create: `packages/pake_cli/lib/src/signing.dart`
- Create: `packages/pake_cli/lib/src/commands/doctor.dart`
- Modify: `packages/pake_cli/lib/src/commands/build.dart`（iOS 平台时先跑签名检查）
- Modify: `packages/pake_cli/lib/src/runner.dart`
- Test: `packages/pake_cli/test/signing_test.dart`

**Interfaces:**
- Consumes: Task 4 `PakeException` / `ExitCodes` / `Output` · Task 9 `ProcessRunner`
- Produces:
  - `class SigningIdentity { const SigningIdentity(this.name); final String name; }`
  - `List<SigningIdentity> parseIdentities(String securityOutput)`
  - `class ProvisioningProfile { const ProvisioningProfile({required this.name, required this.expiry, required this.appId}); bool get isExpired; }`
  - `Future<void> checkIosSigning({required ProcessRunner runner, required String profileName, required String bundleId, required List<ProvisioningProfile> profiles})`

**为何前置检查：** spec 指出自签场景最常见的两个失败是 profile 过期与 bundle id 不匹配。等 `xcodebuild` 跑十分钟再吐一段晦涩报错，是最差的反馈循环。

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/signing_test.dart`：

```dart
import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/process_runner.dart';
import 'package:pake_cli/src/signing.dart';
import 'package:test/test.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.stdout, {this.exitCode = 0});
  final String stdout;
  final int exitCode;

  @override
  Future<ProcessResult> run(String e, List<String> a, {String? workingDirectory}) async =>
      ProcessResult(0, exitCode, stdout, '');
}

void main() {
  group('parseIdentities', () {
    test('extracts identity names from security output', () {
      const output = '''
  1) A1B2C3 "Apple Development: Hao Wang (ABC123)"
  2) D4E5F6 "Apple Distribution: Hao Wang (ABC123)"
     2 valid identities found
''';

      final ids = parseIdentities(output);

      expect(ids.map((i) => i.name), [
        'Apple Development: Hao Wang (ABC123)',
        'Apple Distribution: Hao Wang (ABC123)',
      ]);
    });

    test('returns empty when no identities are found', () {
      expect(parseIdentities('     0 valid identities found\n'), isEmpty);
    });
  });

  group('ProvisioningProfile', () {
    test('is expired when the expiry date is in the past', () {
      final p = ProvisioningProfile(
        name: 'Old',
        expiry: DateTime.now().subtract(const Duration(days: 1)),
        appId: 'ABCDE.com.pake.weibo',
      );
      expect(p.isExpired, isTrue);
    });

    test('is not expired when the expiry date is in the future', () {
      final p = ProvisioningProfile(
        name: 'Fresh',
        expiry: DateTime.now().add(const Duration(days: 30)),
        appId: 'ABCDE.com.pake.weibo',
      );
      expect(p.isExpired, isFalse);
    });
  });

  group('checkIosSigning', () {
    final fresh = ProvisioningProfile(
      name: 'Pake Dev',
      expiry: DateTime.now().add(const Duration(days: 30)),
      appId: 'ABCDE.com.pake.weibo',
    );

    test('passes when a valid identity and matching profile exist', () async {
      await checkIosSigning(
        runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
        profileName: 'Pake Dev',
        bundleId: 'com.pake.weibo',
        profiles: [fresh],
      );
    });

    test('fails with exit code 2 when there is no codesigning identity', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('     0 valid identities found\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.weibo',
          profiles: [fresh],
        ),
        throwsA(isA<PakeException>()
            .having((e) => e.exitCode, 'exitCode', ExitCodes.environment)),
      );
    });

    test('fails when the named profile is missing', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Nonexistent',
          bundleId: 'com.pake.weibo',
          profiles: [fresh],
        ),
        throwsA(isA<PakeException>().having(
            (e) => e.message, 'message', contains('Nonexistent'))),
      );
    });

    test('fails with an explicit message when the profile has expired', () {
      final expired = ProvisioningProfile(
        name: 'Pake Dev',
        expiry: DateTime.now().subtract(const Duration(days: 2)),
        appId: 'ABCDE.com.pake.weibo',
      );

      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.weibo',
          profiles: [expired],
        ),
        throwsA(isA<PakeException>()
            .having((e) => e.message, 'message', contains('expired'))),
      );
    });

    test('fails when the profile app id does not match the bundle id', () {
      expect(
        () => checkIosSigning(
          runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
          profileName: 'Pake Dev',
          bundleId: 'com.pake.other',
          profiles: [fresh],
        ),
        throwsA(isA<PakeException>()
            .having((e) => e.message, 'message', contains('com.pake.other'))),
      );
    });

    test('accepts a wildcard profile app id', () async {
      final wildcard = ProvisioningProfile(
        name: 'Wildcard',
        expiry: DateTime.now().add(const Duration(days: 30)),
        appId: 'ABCDE.*',
      );

      await checkIosSigning(
        runner: _FakeRunner('  1) X "Apple Development: Hao (A)"\n'),
        profileName: 'Wildcard',
        bundleId: 'com.pake.anything',
        profiles: [wildcard],
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart test test/signing_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/signing.dart'`

- [ ] **Step 3: 实现 signing.dart**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'output.dart';
import 'process_runner.dart';

class SigningIdentity {
  const SigningIdentity(this.name);
  final String name;
}

final _identityPattern = RegExp(r'^\s+\d+\)\s+\S+\s+"(.+)"\s*$', multiLine: true);

List<SigningIdentity> parseIdentities(String securityOutput) => _identityPattern
    .allMatches(securityOutput)
    .map((m) => SigningIdentity(m[1]!))
    .toList();

class ProvisioningProfile {
  const ProvisioningProfile({
    required this.name,
    required this.expiry,
    required this.appId,
  });

  final String name;
  final DateTime expiry;

  /// 形如 `TEAMID.com.example.app`，或通配 `TEAMID.*`。
  final String appId;

  bool get isExpired => expiry.isBefore(DateTime.now());

  bool matches(String bundleId) {
    final withoutTeam = appId.contains('.')
        ? appId.substring(appId.indexOf('.') + 1)
        : appId;
    if (withoutTeam == '*') return true;
    if (withoutTeam.endsWith('.*')) {
      return bundleId.startsWith(
        withoutTeam.substring(0, withoutTeam.length - 1),
      );
    }
    return withoutTeam == bundleId;
  }
}

/// 在 build 之前把签名问题挡下来，不等 xcodebuild 输出。
Future<void> checkIosSigning({
  required ProcessRunner runner,
  required String profileName,
  required String bundleId,
  required List<ProvisioningProfile> profiles,
}) async {
  final result = await runner.run(
    'security',
    ['find-identity', '-v', '-p', 'codesigning'],
  );
  if (parseIdentities(result.stdout.toString()).isEmpty) {
    throw PakeException(
      ExitCodes.environment,
      'No codesigning identity found. Open Xcode → Settings → Accounts and '
      'add your Apple ID, or import a signing certificate.',
    );
  }

  final profile = profiles.where((p) => p.name == profileName).firstOrNull;
  if (profile == null) {
    final available = profiles.map((p) => p.name).join(', ');
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" not found. '
      'Available: ${available.isEmpty ? '(none)' : available}',
    );
  }

  if (profile.isExpired) {
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" expired on '
      '${profile.expiry.toIso8601String().split('T').first}. '
      'Regenerate it in Xcode or on the Apple Developer portal.',
    );
  }

  if (!profile.matches(bundleId)) {
    throw PakeException(
      ExitCodes.environment,
      'Provisioning profile "$profileName" is for ${profile.appId}, '
      'which does not cover bundle id "$bundleId".',
    );
  }
}

/// 扫 `~/Library/MobileDevice/Provisioning Profiles/`。
///
/// `.mobileprovision` 是 CMS 签名过的 plist，用 `security cms -D -i` 解出
/// 明文再抓两个字段——比引 plist 解析库轻。
Future<List<ProvisioningProfile>> loadInstalledProfiles(
  ProcessRunner runner, {
  String? home,
}) async {
  final dir = Directory(p.join(
    home ?? Platform.environment['HOME'] ?? '',
    'Library/MobileDevice/Provisioning Profiles',
  ));
  if (!dir.existsSync()) return const [];

  final profiles = <ProvisioningProfile>[];
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.mobileprovision')) continue;

    final decoded = await runner.run('security', ['cms', '-D', '-i', file.path]);
    final xml = decoded.stdout.toString();

    final name = _plistString(xml, 'Name');
    final appId = _plistString(xml, 'application-identifier');
    final expiry = _plistDate(xml, 'ExpirationDate');
    if (name == null || appId == null || expiry == null) continue;

    profiles.add(
      ProvisioningProfile(name: name, expiry: expiry, appId: appId),
    );
  }
  return profiles;
}

String? _plistString(String xml, String key) => RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(xml)?[1];

DateTime? _plistDate(String xml, String key) {
  final raw = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<date>([^<]*)</date>',
  ).firstMatch(xml)?[1];
  return raw == null ? null : DateTime.tryParse(raw);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/signing_test.dart`
Expected: PASS，10 个测试全绿

- [ ] **Step 5: 实现 doctor 命令**

`packages/pake_cli/lib/src/commands/doctor.dart`：

```dart
import 'dart:io';

import 'package:args/command_runner.dart';

import '../output.dart';
import '../process_runner.dart';
import '../signing.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._output, {ProcessRunner? runner})
      : _runner = runner ?? const RealProcessRunner() {
    argParser.addFlag('json', negatable: false);
  }

  final Output _output;
  final ProcessRunner _runner;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check the build environment and signing setup.';

  @override
  Future<int> run() async {
    final checks = <String, Object?>{};

    final flutter = await _runner.run('flutter', ['--version']);
    checks['flutter'] = flutter.exitCode == 0
        ? flutter.stdout.toString().split('\n').first
        : 'NOT FOUND';

    if (Platform.isMacOS) {
      final identities = parseIdentities(
        (await _runner.run('security', ['find-identity', '-v', '-p', 'codesigning']))
            .stdout
            .toString(),
      );
      checks['codesigningIdentities'] = [for (final i in identities) i.name];

      final profiles = await loadInstalledProfiles(_runner);
      checks['provisioningProfiles'] = [
        for (final p in profiles)
          '${p.name} → ${p.appId}'
              '${p.isExpired ? ' (EXPIRED ${p.expiry.toIso8601String().split('T').first})' : ''}',
      ];
    } else {
      checks['ios'] = 'skipped (not macOS)';
    }

    _output.success(checks);
    return checks['flutter'] == 'NOT FOUND' ? ExitCodes.environment : 0;
  }
}
```

- [ ] **Step 6: 在 build 命令里前置签名检查**

在 `BuildCommand.run` 里，解析出 `platforms` 之后、进 `withLock` 之前插入：

```dart
    String? exportOptionsPath;
    if (platforms.contains(PakePlatform.ios)) {
      final teamId = args.option('team-id');
      final profileName = args.option('profile');
      if (teamId == null || profileName == null) {
        throw PakeException(
          ExitCodes.config,
          'iOS builds need --team-id and --profile.',
        );
      }

      await checkIosSigning(
        runner: _runner,
        profileName: profileName,
        bundleId: config.bundleId,
        profiles: await loadInstalledProfiles(_runner),
      );

      exportOptionsPath = p.join(_workspace.root, 'ExportOptions.plist');
      File(exportOptionsPath).writeAsStringSync(exportOptionsPlist(
        teamId: teamId,
        profileName: profileName,
        bundleId: config.bundleId,
      ));
    }
```

并把 `exportOptionsPath` 传给 `runBuild`。

- [ ] **Step 7: 挂到 runner，跑全量测试，手验 doctor**

在 `runner.dart` 加 `..addCommand(DoctorCommand(output))`。

Run: `cd packages/pake_cli && dart test && dart run bin/pakem.dart doctor`
Expected: 测试全绿；`doctor` 打印出 flutter 版本与本机证书 / profile 列表

- [ ] **Step 8: 提交**

```bash
git add packages/pake_cli
git commit -m "feat(cli): add doctor and pre-flight iOS signing checks"
```

---

### Task 12: pake_shell 骨架与两层配置的运行期读写

**Files:**
- Create: `packages/pake_shell/`（用 `flutter create` 生成）
- Modify: `packages/pake_shell/pubspec.yaml`
- Create: `packages/pake_shell/lib/src/runtime_config.dart`
- Create: `packages/pake_shell/assets/pake.json`（占位，供本地 `flutter run` 用）
- Test: `packages/pake_shell/test/runtime_config_test.dart`

**Interfaces:**
- Consumes: Task 1 `PakeConfig` · Task 3 `RuntimeKeys` / `UserAgentPresets`
- Produces:
  - `class RuntimeConfig { static Future<RuntimeConfig> load(); String get url; set url(String v); String get userAgent; set userAgent(String v); Set<String> get enabledScripts; void setScriptEnabled(String id, bool on); void reset(); PakeConfig get buildTime; }`

**这是 spec「配置分两层」的落点。** 三条不变量必须由测试钉死：
1. runtime 层为空时，读回来的是 build-time 层的值。
2. 设置页只写 runtime 层，build-time 层永远不被改。
3. `reset()` = 清空 runtime 层，回落构建时默认。

第 4 条来自 spec 的错误处理章节：`get_storage` 读到**损坏配置**必须回落默认而不是崩溃。

- [ ] **Step 1: 生成 Flutter 项目并改 pubspec**

```bash
cd packages && flutter create --org com.example --platforms=android,ios --project-name pake_shell pake_shell
```

`packages/pake_shell/pubspec.yaml` 的依赖段改成：

```yaml
environment:
  sdk: ^3.8.0
  flutter: ">=3.32.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.2.0-beta.3
  get_storage: ^2.1.1
  pake_config:
    path: ../pake_config
  debug_sheet:
    git:
      url: https://github.com/sunbird89629/debug_sheet.git
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git

flutter:
  uses-material-design: true
  assets:
    - assets/pake.json
    - assets/scripts/
```

> `flutter_inappwebview` 用 pub.dev 的 beta，**不 fork**。遇坑时按文档开头「fork 时的关键细节」那段处理。

- [ ] **Step 2: 验证依赖能解析**

Run: `cd packages/pake_shell && flutter pub get`
Expected: 成功。若 `get_storage 2.1.1` 与 Flutter 3.41 冲突，**立刻停下报告**——这是 spec 未预见的风险，需要人决定换 `shared_preferences` 还是打 patch，而不是自行改设计。

- [ ] **Step 3: 写失败的测试**

`packages/pake_shell/test/runtime_config_test.dart`：

```dart
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
    await GetStorage.init();
    await GetStorage().erase();
  });

  test('falls back to the build-time url when runtime is empty', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.url, 'https://m.weibo.cn');
  });

  test('a runtime write wins over the build-time default', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)..url = 'https://other.com';

    expect(c.url, 'https://other.com');
    expect(RuntimeConfig.fromBuildTime(_buildTime).url, 'https://other.com',
        reason: 'the write must persist across instances');
  });

  test('writing runtime config never mutates the build-time layer', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)..url = 'https://other.com';

    expect(c.buildTime.url, 'https://m.weibo.cn');
  });

  test('reset clears the runtime layer and falls back again', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime)
      ..url = 'https://other.com'
      ..userAgent = 'custom-ua';

    c.reset();

    expect(c.url, 'https://m.weibo.cn');
    expect(c.userAgent, isEmpty, reason: 'empty means "use the system default"');
  });

  test('all inject scripts are enabled by default', () {
    final c = RuntimeConfig.fromBuildTime(_buildTime);

    expect(c.enabledScripts, {'hide-ads.js'});
  });

  test('toggling a script off persists', () {
    RuntimeConfig.fromBuildTime(_buildTime).setScriptEnabled('hide-ads.js', false);

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
}
```

- [ ] **Step 4: 跑测试确认失败**

Run: `cd packages/pake_shell && flutter test test/runtime_config_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_shell/src/runtime_config.dart'`

- [ ] **Step 5: 实现 runtime_config.dart**

```dart
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

  bool get fullscreen => _box.read<Object?>(RuntimeKeys.fullscreen) is bool
      ? _box.read<bool>(RuntimeKeys.fullscreen)!
      : true;
  set fullscreen(bool value) => _box.write(RuntimeKeys.fullscreen, value);

  /// 默认全开——构建时特意打包进来的脚本，默认不生效才是意外。
  Set<String> get enabledScripts {
    final stored = _box.read<Object?>(RuntimeKeys.enabledScripts);
    if (stored is! List) return buildTime.injectScripts.toSet();
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
    ]) {
      _box.remove(key);
    }
  }

  /// 存进去的值类型不对（人手改过、旧版本遗留）时回落，而不是抛异常。
  String? _readString(String key) {
    final value = _box.read<Object?>(key);
    return value is String && value.isNotEmpty ? value : null;
  }
}
```

- [ ] **Step 6: 跑测试确认通过**

Run: `cd packages/pake_shell && flutter test test/runtime_config_test.dart`
Expected: PASS，8 个测试全绿

- [ ] **Step 7: 提交**

```bash
git add packages/pake_shell
git commit -m "feat(shell): add two-layer runtime config with corrupt-value fallback"
```

---

### Task 13: WebView 主界面与错误页

**Files:**
- Create: `packages/pake_shell/lib/src/error_page.dart`
- Create: `packages/pake_shell/lib/src/webview_page.dart`
- Create: `packages/pake_shell/lib/src/app.dart`
- Modify: `packages/pake_shell/lib/main.dart`
- Test: `packages/pake_shell/test/error_page_test.dart`

**Interfaces:**
- Consumes: Task 12 `RuntimeConfig` · Task 3 `UserAgentPresets`
- Produces:
  - `enum LoadFailureKind { offline, badUrl, serverError }`
  - `LoadFailureKind classifyFailure({int? httpStatus, String? errorType})`
  - `class ErrorPage extends StatelessWidget { const ErrorPage({required this.kind, required this.url, required this.onRetry, required this.onOpenSettings}); }`
  - `class WebViewPage extends StatefulWidget { const WebViewPage({required this.config, required this.onOpenSettings}); }`
  - `class PakeApp extends StatefulWidget`

**为何错误页要分类：** spec 明确「区分『无网络』与『URL 错误』，提示不同：前者让用户等待，后者引导用户改配置」。给无网络的人一个「改 URL」按钮是误导。

**为何错误页也要有「打开设置」按钮：** EscapeHatch 是兜底通道，但有明确错误页时应给明确按钮——白屏被困是这类 app 最常见的失效方式。

- [ ] **Step 1: 写失败的测试**

`packages/pake_shell/test/error_page_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/error_page.dart';

void main() {
  group('classifyFailure', () {
    test('maps host-lookup failures to offline', () {
      expect(
        classifyFailure(errorType: 'HOST_LOOKUP'),
        LoadFailureKind.offline,
      );
      expect(
        classifyFailure(errorType: 'CONNECT'),
        LoadFailureKind.offline,
      );
    });

    test('maps 404 to a bad url', () {
      expect(classifyFailure(httpStatus: 404), LoadFailureKind.badUrl);
    });

    test('maps 5xx to a server error, not a bad url', () {
      expect(classifyFailure(httpStatus: 503), LoadFailureKind.serverError);
    });

    test('maps unresolvable-host errors to a bad url, not offline', () {
      expect(
        classifyFailure(errorType: 'UNKNOWN_HOST'),
        LoadFailureKind.badUrl,
      );
    });
  });

  group('ErrorPage', () {
    Future<void> pump(WidgetTester tester, LoadFailureKind kind) =>
        tester.pumpWidget(MaterialApp(
          home: ErrorPage(
            kind: kind,
            url: 'https://m.weibo.cn',
            onRetry: () {},
            onOpenSettings: () {},
          ),
        ));

    testWidgets('offline tells the user to wait, and offers no url edit',
        (tester) async {
      await pump(tester, LoadFailureKind.offline);

      expect(find.textContaining('network'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('bad url guides the user into settings', (tester) async {
      await pump(tester, LoadFailureKind.badUrl);

      expect(find.text('Open settings'), findsOneWidget);
      expect(find.textContaining('https://m.weibo.cn'), findsOneWidget);
    });

    testWidgets('every failure kind offers an escape into settings',
        (tester) async {
      // 白屏被困是这类 app 最常见的失效方式——每种错误都必须有出口。
      for (final kind in LoadFailureKind.values) {
        await pump(tester, kind);
        expect(find.text('Open settings'), findsOneWidget, reason: '$kind');
      }
    });

    testWidgets('retry fires the callback', (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        home: ErrorPage(
          kind: LoadFailureKind.offline,
          url: 'https://m.weibo.cn',
          onRetry: () => retried = true,
          onOpenSettings: () {},
        ),
      ));

      await tester.tap(find.text('Retry'));

      expect(retried, isTrue);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_shell && flutter test test/error_page_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_shell/src/error_page.dart'`

- [ ] **Step 3: 实现 error_page.dart**

```dart
import 'package:flutter/material.dart';

enum LoadFailureKind { offline, badUrl, serverError }

/// 分类决定给用户什么建议。给断网的人一个「改 URL」按钮是误导。
LoadFailureKind classifyFailure({int? httpStatus, String? errorType}) {
  if (httpStatus != null) {
    return httpStatus >= 500 ? LoadFailureKind.serverError : LoadFailureKind.badUrl;
  }

  return switch (errorType?.toUpperCase()) {
    'HOST_LOOKUP' || 'CONNECT' || 'IO' || 'TIMEOUT' => LoadFailureKind.offline,
    'UNKNOWN_HOST' || 'BAD_URL' || 'UNSUPPORTED_SCHEME' => LoadFailureKind.badUrl,
    _ => LoadFailureKind.serverError,
  };
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.kind,
    required this.url,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LoadFailureKind kind;
  final String url;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  String get _message => switch (kind) {
        LoadFailureKind.offline =>
          'No network connection. Check your Wi-Fi or mobile data, then retry.',
        LoadFailureKind.badUrl =>
          'Could not load $url. The address may be wrong — open settings to change it.',
        LoadFailureKind.serverError =>
          'The server at $url returned an error. It may be temporarily down.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kind == LoadFailureKind.offline
                      ? Icons.wifi_off
                      : Icons.error_outline,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(_message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                const SizedBox(height: 8),
                // EscapeHatch 是兜底通道，但有明确错误页时应给明确按钮。
                TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_shell && flutter test test/error_page_test.dart`
Expected: PASS，8 个测试全绿

- [ ] **Step 5: 实现 webview_page.dart**

WebView 本身需要真机，不写 widget test（spec 的测试策略如此规定）。

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger_utils/logger_utils.dart';

import 'error_page.dart';
import 'runtime_config.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.config,
    required this.onOpenSettings,
  });

  final RuntimeConfig config;
  final VoidCallback onOpenSettings;

  @override
  State<WebViewPage> createState() => WebViewPageState();
}

class WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? _controller;
  LoadFailureKind? _failure;
  List<UserScript> _scripts = const [];

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  /// 读构建期物化出的脚本清单，按运行期开关过滤。
  Future<void> _loadScripts() async {
    final enabled = widget.config.enabledScripts;
    final scripts = <UserScript>[];

    try {
      final manifest = jsonDecode(
        await rootBundle.loadString('assets/scripts/index.json'),
      ) as List<Object?>;

      for (final entry in manifest.whereType<Map<String, Object?>>()) {
        final id = entry['id']! as String;
        if (!enabled.contains(id)) continue;

        scripts.add(UserScript(
          groupName: id,
          source: await rootBundle.loadString('assets/scripts/$id.js'),
          // CSS 要等 DOM 有 head，hook 类脚本必须抢在页面脚本之前。
          injectionTime: entry['kind'] == 'css'
              ? UserScriptInjectionTime.AT_DOCUMENT_END
              : UserScriptInjectionTime.AT_DOCUMENT_START,
        ));
      }
    } catch (e) {
      devLogger.warning('no inject scripts loaded: $e');
    }

    if (mounted) setState(() => _scripts = scripts);
  }

  /// 开关只在下一次页面加载生效（`WKUserContentController` 的语义），
  /// 所以设置页拨完开关必须调这个。
  Future<void> reloadWithCurrentSettings() async {
    await _loadScripts();
    await _controller?.setSettings(settings: _settings);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.config.url)),
    );
    if (mounted) setState(() => _failure = null);
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        userAgent: widget.config.userAgent,
        javaScriptEnabled: true,
        useOnLoadResource: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: false,
      );

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return ErrorPage(
        kind: failure,
        url: widget.config.url,
        onRetry: reloadWithCurrentSettings,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    return InAppWebView(
      key: ValueKey(_scripts.length),
      initialUrlRequest: URLRequest(url: WebUri(widget.config.url)),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView(_scripts),
      onWebViewCreated: (c) => _controller = c,
      onConsoleMessage: (_, msg) =>
          devLogger.info('[console] ${msg.message}'),
      onReceivedError: (_, __, error) {
        devLogger.severe('load error: ${error.type} ${error.description}');
        setState(() => _failure = classifyFailure(errorType: error.type.name));
      },
      onReceivedHttpError: (_, __, response) {
        devLogger.severe('http error: ${response.statusCode}');
        setState(
          () => _failure = classifyFailure(httpStatus: response.statusCode),
        );
      },
    );
  }
}
```

> `UnmodifiableListView` 来自 `dart:collection`，记得 import。

- [ ] **Step 6: 实现 app.dart 与 main.dart**

`lib/src/app.dart`：

```dart
import 'package:flutter/material.dart';

import 'runtime_config.dart';
import 'webview_page.dart';

class PakeApp extends StatefulWidget {
  const PakeApp({super.key, required this.config});

  final RuntimeConfig config;

  @override
  State<PakeApp> createState() => _PakeAppState();
}

class _PakeAppState extends State<PakeApp> {
  final _webViewKey = GlobalKey<WebViewPageState>();

  void _openSettings() {
    // Task 15 会把 DebugDrawer 挂上来。
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.config.buildTime.name,
      debugShowCheckedModeBanner: false,
      home: Stack(
        children: [
          WebViewPage(
            key: _webViewKey,
            config: widget.config,
            onOpenSettings: _openSettings,
          ),
          // Task 14 会在这里加 EscapeHatch。
        ],
      ),
    );
  }
}
```

`lib/main.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger_utils/logger_utils.dart';

import 'src/app.dart';
import 'src/runtime_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging(filePrefix: 'pake');
  // debug_sheet 的输入历史也写这个默认容器，必须在 runApp 前初始化。
  await GetStorage.init();

  runApp(PakeApp(config: await RuntimeConfig.load()));
}
```

- [ ] **Step 7: 真机验一次**

```bash
cd packages/pake_shell
echo '{"name":"Demo","url":"https://example.com","bundleId":"com.example.demo","version":"1.0.0","buildNumber":1,"injectScripts":[],"permissions":[]}' > assets/pake.json
flutter run
```
Expected: 全屏加载 example.com。把 URL 改成 `https://nonexistent.invalid` 重跑，应看到「Could not load…」错误页与两个按钮。

- [ ] **Step 8: 提交**

```bash
git add packages/pake_shell
git commit -m "feat(shell): add fullscreen webview with classified error page"
```

---

### Task 14: EscapeHatch —— 角落隐形长按手势

**Files:**
- Create: `packages/pake_shell/lib/src/escape_hatch.dart`
- Modify: `packages/pake_shell/lib/src/app.dart`
- Test: `packages/pake_shell/test/escape_hatch_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class EscapeHatch extends StatelessWidget { const EscapeHatch({required this.onTriggered}); final VoidCallback onTriggered; }`

**为何必须在 Flutter 层：** `InAppWebView` 吞掉所有触摸事件，设置壳入口不能依赖网页内按钮。更关键的是网页白屏时用户仍须能进设置页改回 URL，否则 app 变砖。

**实现要点：** Flutter 的 `GestureDetector.onLongPress` 是 **500ms**，而 spec 要 **1.5 秒**（防误触）。必须用 `RawGestureDetector` + 自定义 `LongPressGestureRecognizer(duration:)`，`GestureDetector` 没有暴露时长参数。

- [ ] **Step 1: 写失败的测试**

`packages/pake_shell/test/escape_hatch_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/escape_hatch.dart';

void main() {
  Future<int> pumpAndHold(WidgetTester tester, Duration hold) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
          EscapeHatch(onTriggered: () => count++),
        ],
      ),
    ));

    final gesture = await tester.startGesture(const Offset(10, 10));
    await tester.pump(hold);
    await gesture.up();
    await tester.pumpAndSettle();
    return count;
  }

  testWidgets('a 1.5s long press triggers it', (tester) async {
    expect(await pumpAndHold(tester, const Duration(milliseconds: 1600)), 1);
  });

  testWidgets('a normal 500ms long press does NOT trigger it', (tester) async {
    // 用默认的 500ms 就会误触——这正是要自定义 duration 的原因。
    expect(await pumpAndHold(tester, const Duration(milliseconds: 600)), 0);
  });

  testWidgets('a tap does not trigger it', (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [EscapeHatch(onTriggered: () => count++)]),
    ));

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(count, 0);
  });

  testWidgets('it occupies a 44x44 area pinned to the top-left corner',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [EscapeHatch(onTriggered: () {})]),
    ));

    final box = tester.getRect(find.byType(EscapeHatch));

    expect(box.width, 44);
    expect(box.height, 44);
    expect(box.topLeft, Offset.zero);
  });

  testWidgets('a press outside the corner does not trigger it', (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [EscapeHatch(onTriggered: () => count++)]),
    ));

    final gesture = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(count, 0);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_shell && flutter test test/escape_hatch_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_shell/src/escape_hatch.dart'`

- [ ] **Step 3: 实现 escape_hatch.dart**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 左上角 44×44 的透明手势区，长按 1.5 秒打开设置。
///
/// 必须在 Flutter 层而非网页内：`InAppWebView` 吞掉所有触摸事件，
/// 且网页白屏时用户仍须能进设置改回 URL，否则 app 变砖。
class EscapeHatch extends StatelessWidget {
  const EscapeHatch({super.key, required this.onTriggered});

  final VoidCallback onTriggered;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      // GestureDetector.onLongPress 写死 500ms，太容易误触，
      // 所以这里下沉到 RawGestureDetector 自定义时长。
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: const Duration(milliseconds: 1500),
            ),
            (recognizer) => recognizer.onLongPress = onTriggered,
          ),
        },
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_shell && flutter test test/escape_hatch_test.dart`
Expected: PASS，5 个测试全绿

- [ ] **Step 5: 挂进 app.dart**

把 `app.dart` 的 `Stack` 注释替换为：

```dart
          EscapeHatch(onTriggered: _openSettings),
```

- [ ] **Step 6: 提交**

```bash
git add packages/pake_shell
git commit -m "feat(shell): add corner escape hatch with 1.5s long press"
```

---

### Task 15: DebugDrawer 设置壳

**Files:**
- Create: `packages/pake_shell/lib/src/debug_drawer.dart`
- Create: `packages/pake_shell/lib/src/log_page.dart`
- Modify: `packages/pake_shell/lib/src/app.dart`（`_openSettings` 真正 push）
- Test: `packages/pake_shell/test/debug_drawer_test.dart`

**Interfaces:**
- Consumes: Task 12 `RuntimeConfig` · Task 3 `UserAgentPresets` · `debug_sheet` 的 `DebugInputSheet` / `DebugSelectSheet`
- Produces:
  - `class DebugDrawer extends StatefulWidget { const DebugDrawer({required this.config, required this.onReloadRequested, required this.onClearCache}); }`
  - `List<String> uaPresetOrder(String currentUa)` —— 把当前 UA 排到首位，绕开 `DebugSelectSheet` 没有 `initialIndex` 的限制
  - `class LogPage extends StatelessWidget`

**三个 `debug_sheet` 集成坑（详见文档开头）：** 无 `initialIndex`、`DebugInputSheet` 需有界高度、pop 可能返回 `null`。

**脚本开关的 UI 契约：** `addUserScript` / `removeUserScript` 只在下一次页面加载生效（`WKUserContentController` 的语义）。所以拨开关的实际行为是「改配置 → 自动 reload」。**UI 必须明示这一点**，否则用户会以为开关坏了。

- [ ] **Step 1: 写失败的测试**

`packages/pake_shell/test/debug_drawer_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pake_config/pake_config.dart';
import 'package:pake_shell/src/debug_drawer.dart';
import 'package:pake_shell/src/runtime_config.dart';

const _buildTime = PakeConfig(
  name: 'Weibo',
  url: 'https://m.weibo.cn',
  bundleId: 'com.pake.weibo',
  injectScripts: ['hide-ads.js', 'fix-video.js'],
);

void main() {
  late RuntimeConfig config;
  late int reloadCount;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GetStorage.init();
    await GetStorage().erase();
    config = RuntimeConfig.fromBuildTime(_buildTime);
    reloadCount = 0;
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: DebugDrawer(
          config: config,
          onReloadRequested: () => reloadCount++,
          onClearCache: () async {},
        ),
      ));

  group('uaPresetOrder', () {
    test('puts the current UA first so the sheet preselects it', () {
      // DebugSelectSheet 没有 initialIndex，_selectedIndex 恒从 0 起。
      final order = uaPresetOrder(UserAgentPresets.all['Desktop']!);

      expect(order.first, 'Desktop');
    });

    test('puts Default first when no UA override is set', () {
      expect(uaPresetOrder('').first, 'Default');
    });

    test('puts Custom first when the UA matches no preset', () {
      final order = uaPresetOrder('my-weird-ua/1.0');

      expect(order.first, 'Custom…');
    });

    test('always offers every preset plus Custom exactly once', () {
      final order = uaPresetOrder('');

      expect(order.toSet().length, order.length);
      expect(order, containsAll(UserAgentPresets.all.keys));
      expect(order, contains('Custom…'));
    });
  });

  group('DebugDrawer', () {
    testWidgets('lists one switch per inject script', (tester) async {
      await pump(tester);

      expect(find.text('hide-ads.js'), findsOneWidget);
      expect(find.text('fix-video.js'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(2));
    });

    testWidgets('every script starts enabled', (tester) async {
      await pump(tester);

      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.every((s) => s.value), isTrue);
    });

    testWidgets('toggling a script persists it and triggers a reload',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(config.enabledScripts, isNot(contains('hide-ads.js')));
      expect(reloadCount, 1, reason: 'scripts only take effect on next load');
    });

    testWidgets('states plainly that toggles apply on reload', (tester) async {
      // 不写清楚，用户会以为开关坏了。
      await pump(tester);

      expect(find.textContaining('reload'), findsWidgets);
    });

    testWidgets('reset restores the build-time url and reloads', (tester) async {
      config.url = 'https://changed.example.com';
      await pump(tester);

      await tester.tap(find.text('Reset to build defaults'));
      await tester.pumpAndSettle();

      expect(config.url, 'https://m.weibo.cn');
      expect(reloadCount, 1);
    });

    testWidgets('shows the current url so the user knows what is loaded',
        (tester) async {
      await pump(tester);

      expect(find.textContaining('https://m.weibo.cn'), findsWidgets);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_shell && flutter test test/debug_drawer_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_shell/src/debug_drawer.dart'`

- [ ] **Step 3: 实现 debug_drawer.dart**

```dart
import 'package:debug_sheet/debug_sheet.dart';
import 'package:flutter/material.dart';
import 'package:pake_config/pake_config.dart';

import 'log_page.dart';
import 'runtime_config.dart';

const _customLabel = 'Custom…';

/// `DebugSelectSheet` 没有 `initialIndex`，`_selectedIndex` 恒从 0 起。
/// 把当前值排到首位即可预选，无需改上游包。
List<String> uaPresetOrder(String currentUa) {
  final names = [...UserAgentPresets.all.keys, _customLabel];
  final current = UserAgentPresets.all.entries
          .where((e) => e.value == currentUa)
          .map((e) => e.key)
          .firstOrNull ??
      _customLabel;

  return [current, ...names.where((n) => n != current)];
}

class DebugDrawer extends StatefulWidget {
  const DebugDrawer({
    super.key,
    required this.config,
    required this.onReloadRequested,
    required this.onClearCache,
  });

  final RuntimeConfig config;
  final VoidCallback onReloadRequested;
  final Future<void> Function() onClearCache;

  @override
  State<DebugDrawer> createState() => _DebugDrawerState();
}

class _DebugDrawerState extends State<DebugDrawer> {
  RuntimeConfig get _config => widget.config;

  /// `DebugInputSheet` 内部用了 Expanded + ListView，
  /// 必须给有界高度，否则布局崩。
  Future<T?> _showSheet<T>(Widget child) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: child,
        ),
      );

  Future<void> _editUrl() async {
    final entered =
        await _showSheet<String>(const DebugInputSheet(title: 'Load URL'));
    // 下滑取消时返回 null——不能直接 `!`。
    if (entered == null || entered.isEmpty) return;

    _config.url = entered;
    setState(() {});
    widget.onReloadRequested();
  }

  Future<void> _editUserAgent() async {
    final order = uaPresetOrder(_config.userAgent);
    final index = await _showSheet<int>(
      DebugSelectSheet(title: 'User agent', items: order),
    );
    if (index == null) return;

    final choice = order[index];
    if (choice == _customLabel) {
      final custom = await _showSheet<String>(
        const DebugInputSheet(title: 'Custom user agent'),
      );
      if (custom == null || custom.isEmpty) return;
      _config.userAgent = custom;
    } else {
      _config.userAgent = UserAgentPresets.all[choice]!;
    }

    setState(() {});
    widget.onReloadRequested();
  }

  void _toggleScript(String id, bool enabled) {
    _config.setScriptEnabled(id, enabled);
    setState(() {});
    // addUserScript/removeUserScript 只在下一次加载生效，所以必须 reload。
    widget.onReloadRequested();
  }

  void _reset() {
    _config.reset();
    setState(() {});
    widget.onReloadRequested();
  }

  @override
  Widget build(BuildContext context) {
    final scripts = _config.buildTime.injectScripts;
    final enabled = _config.enabledScripts;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('URL'),
            subtitle: Text(_config.url),
            trailing: const Icon(Icons.edit),
            onTap: _editUrl,
          ),
          ListTile(
            title: const Text('User agent'),
            subtitle: Text(
              _config.userAgent.isEmpty ? 'System default' : _config.userAgent,
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editUserAgent,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Inject scripts'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Toggling a script reloads the page — scripts only take effect '
              'on the next page load.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final id in scripts)
            SwitchListTile(
              title: Text(id),
              value: enabled.contains(id),
              onChanged: (on) => _toggleScript(id, on),
            ),
          const Divider(),
          ListTile(
            title: const Text('Clear cache & cookies'),
            leading: const Icon(Icons.delete_sweep),
            onTap: () async {
              await widget.onClearCache();
              widget.onReloadRequested();
            },
          ),
          ListTile(
            title: const Text('View logs'),
            leading: const Icon(Icons.article),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LogPage()),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Reset to build defaults'),
            leading: const Icon(Icons.restart_alt),
            onTap: _reset,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 实现 log_page.dart**

`logger_utils` 的 file sink 是 daily-rotated，默认目录由 `initLogging(logsDir:)` 决定；不传时它落在应用文档目录。

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 读回 logger_utils 的 daily-rotated file sink。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _content = 'Loading…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = Directory.current;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('pake') && f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      setState(() => _content =
          files.isEmpty ? 'No log files yet.' : files.first.readAsStringSync());
    } catch (e) {
      setState(() => _content = 'Could not read logs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: _content)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          _content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}
```

> **实现时先确认 `initLogging` 的落盘目录**：读一遍 `~/ai/mobile/logger_utils/lib/app_logger.dart` 的 `_fileSink`，把 `LogPage._load` 的目录改成它实际用的那个（很可能要在 `main.dart` 里用 `path_provider` 显式传 `logsDir`）。上面用 `Directory.current` 只是占位，**在移动端几乎肯定不对**。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_shell && flutter test test/debug_drawer_test.dart`
Expected: PASS，11 个测试全绿

- [ ] **Step 6: 接进 app.dart**

`_PakeAppState` 的 `_openSettings` 改为：

```dart
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _openSettings() {
    _navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => DebugDrawer(
        config: widget.config,
        onReloadRequested: () =>
            _webViewKey.currentState?.reloadWithCurrentSettings(),
        onClearCache: () async {
          await InAppWebViewController.clearAllCache();
          await CookieManager.instance().deleteAllCookies();
          await WebStorageManager.instance().deleteAllData();
        },
      ),
    ));
  }
```

并把 `MaterialApp` 加上 `navigatorKey: _navigatorKey`。

- [ ] **Step 7: 真机验一次**

Run: `cd packages/pake_shell && flutter run`
Expected: 左上角长按 1.5 秒打开设置页；改 URL 后网页跳转；切 UA 后 reload

- [ ] **Step 8: 提交**

```bash
git add packages/pake_shell
git commit -m "feat(shell): add debug drawer with url, ua, script toggles and logs"
```

---

### Task 16: 网络检查

**Files:**
- Create: `packages/pake_shell/lib/src/net/net_record.dart`
- Create: `packages/pake_shell/lib/src/net/net_log.dart`
- Create: `packages/pake_shell/assets/net_hook.js`
- Create: `packages/pake_shell/lib/src/net/net_log_page.dart`
- Modify: `packages/pake_shell/lib/src/webview_page.dart`（注入 hook + 挂 handler + `onLoadResource`）
- Modify: `packages/pake_shell/lib/src/debug_drawer.dart`（加「View requests」入口）
- Modify: `packages/pake_shell/pubspec.yaml`（assets 加 `assets/net_hook.js`）
- Test: `packages/pake_shell/test/net_log_test.dart`

**Interfaces:**
- Consumes: Task 13 `WebViewPage`
- Produces:
  - `class NetRecord { const NetRecord({required this.url, required this.method, required this.status, required this.durationMs, required this.at, this.body, this.source = NetSource.js}); String toCurl(); }`
  - `enum NetSource { js, resource }`
  - `class NetLog { NetLog({int capacity = 200}); void add(NetRecord r); List<NetRecord> get records; Stream<void> get changes; void clear(); }`
  - `class NetLogPage extends StatefulWidget { const NetLogPage({required this.log}); }`

**为何自建：** `http_inspector` 是 Dio interceptor，而 WebView 请求走原生网络栈不经 Dio；其 UI 层也因 `HttpRecord` 直接依赖 dio 而不可复用（见文档开头「探查结论」）。

**两个手段互补：** JS hook 覆盖页面内 JS 发起的请求且**能拿到 body**；`onLoadResource` 覆盖 document / 图片 / CSS / 字体，但**只有 URL 与时序**。

- [ ] **Step 1: 写失败的测试**

`packages/pake_shell/test/net_log_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/net/net_log.dart';
import 'package:pake_shell/src/net/net_record.dart';

NetRecord _rec(String url, {int status = 200}) => NetRecord(
      url: url,
      method: 'GET',
      status: status,
      durationMs: 12,
      at: DateTime(2026, 7, 30),
    );

void main() {
  group('NetLog', () {
    test('keeps the most recent records first', () {
      final log = NetLog()
        ..add(_rec('https://a.com'))
        ..add(_rec('https://b.com'));

      expect(log.records.first.url, 'https://b.com');
    });

    test('drops the oldest record once capacity is exceeded', () {
      final log = NetLog(capacity: 2)
        ..add(_rec('https://1.com'))
        ..add(_rec('https://2.com'))
        ..add(_rec('https://3.com'));

      expect(log.records.length, 2);
      expect(log.records.map((r) => r.url), ['https://3.com', 'https://2.com']);
    });

    test('notifies listeners on add', () async {
      final log = NetLog();
      final future = log.changes.first;

      log.add(_rec('https://a.com'));

      await expectLater(future, completes);
    });

    test('clear empties the buffer', () {
      final log = NetLog()..add(_rec('https://a.com'));

      log.clear();

      expect(log.records, isEmpty);
    });
  });

  group('NetRecord.toCurl', () {
    test('emits a runnable curl command', () {
      final curl = NetRecord(
        url: 'https://api.example.com/v1/items?q=1',
        method: 'POST',
        status: 201,
        durationMs: 40,
        at: DateTime(2026, 7, 30),
        requestHeaders: const {'Content-Type': 'application/json'},
        requestBody: '{"a":1}',
      ).toCurl();

      expect(curl, startsWith("curl -X POST 'https://api.example.com/v1/items?q=1'"));
      expect(curl, contains("-H 'Content-Type: application/json'"));
      expect(curl, contains("""--data-raw '{"a":1}'"""));
    });

    test('escapes single quotes so the command stays valid', () {
      final curl = NetRecord(
        url: 'https://a.com',
        method: 'POST',
        status: 200,
        durationMs: 1,
        at: DateTime(2026, 7, 30),
        requestBody: "it's",
      ).toCurl();

      expect(curl, contains(r"'it'\''s'"));
    });

    test('omits the data flag for GET requests without a body', () {
      expect(_rec('https://a.com').toCurl(), isNot(contains('--data-raw')));
    });
  });

  group('NetRecord.fromHandlerJson', () {
    test('parses what net_hook.js posts over callHandler', () {
      final r = NetRecord.fromHandlerJson({
        'url': 'https://api.example.com/x',
        'method': 'GET',
        'status': 200,
        'ms': 33,
        'body': '{"ok":true}',
      });

      expect(r.url, 'https://api.example.com/x');
      expect(r.durationMs, 33);
      expect(r.body, '{"ok":true}');
      expect(r.source, NetSource.js);
    });

    test('survives a malformed payload without throwing', () {
      final r = NetRecord.fromHandlerJson({'url': 12345, 'status': 'nope'});

      expect(r.url, isNotEmpty);
      expect(r.status, -1);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_shell && flutter test test/net_log_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_shell/src/net/net_log.dart'`

- [ ] **Step 3: 实现 net_record.dart**

```dart
enum NetSource {
  /// 来自注入的 fetch/XHR hook——有 body。
  js,

  /// 来自 onLoadResource——只有 URL 与时序。
  resource,
}

class NetRecord {
  const NetRecord({
    required this.url,
    required this.method,
    required this.status,
    required this.durationMs,
    required this.at,
    this.body,
    this.requestBody,
    this.requestHeaders = const {},
    this.source = NetSource.js,
  });

  /// 解析 net_hook.js 经 callHandler 回传的对象。
  ///
  /// 一律防御性取值：页面里的脚本能改 `window.fetch` 的参数形状，
  /// 一个畸形 payload 不该让请求面板崩掉。
  factory NetRecord.fromHandlerJson(Map<Object?, Object?> json) => NetRecord(
        url: json['url'] is String ? json['url']! as String : '(unknown)',
        method: json['method'] is String ? json['method']! as String : 'GET',
        status: json['status'] is int ? json['status']! as int : -1,
        durationMs: json['ms'] is int ? json['ms']! as int : 0,
        at: DateTime.now(),
        body: json['body'] is String ? json['body']! as String : null,
      );

  final String url;
  final String method;

  /// `-1` 表示请求失败或状态未知。
  final int status;
  final int durationMs;
  final DateTime at;
  final String? body;
  final String? requestBody;
  final Map<String, String> requestHeaders;
  final NetSource source;

  String toCurl() {
    final parts = <String>["curl -X $method '${_shellEscape(url)}'"];
    for (final entry in requestHeaders.entries) {
      parts.add("-H '${_shellEscape('${entry.key}: ${entry.value}')}'");
    }
    final rb = requestBody;
    if (rb != null && rb.isNotEmpty) {
      parts.add("--data-raw '${_shellEscape(rb)}'");
    }
    return parts.join(' ');
  }
}

/// 单引号内的单引号必须写成 `'\''`，否则拼出来的命令不合法。
String _shellEscape(String value) => value.replaceAll("'", r"'\''");
```

- [ ] **Step 4: 实现 net_log.dart**

```dart
import 'dart:async';

import 'net_record.dart';

/// 环形缓冲，保留最近 [capacity] 条。
///
/// WebView 一个页面能发几千个请求，无上限缓冲会吃光内存。
class NetLog {
  NetLog({this.capacity = 200});

  final int capacity;
  final _records = <NetRecord>[];
  final _controller = StreamController<void>.broadcast();

  /// 最新的在前。
  List<NetRecord> get records => List.unmodifiable(_records.reversed);

  Stream<void> get changes => _controller.stream;

  void add(NetRecord record) {
    _records.add(record);
    if (_records.length > capacity) _records.removeAt(0);
    if (!_controller.isClosed) _controller.add(null);
  }

  void clear() {
    _records.clear();
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd packages/pake_shell && flutter test test/net_log_test.dart`
Expected: PASS，9 个测试全绿

- [ ] **Step 6: 写 net_hook.js**

`packages/pake_shell/assets/net_hook.js`：

```javascript
(function () {
  if (window.__pakeNetHooked) return;
  window.__pakeNetHooked = true;

  var MAX_BODY = 8192;

  function post(rec) {
    try {
      window.flutter_inappwebview.callHandler('pakeNet', rec);
    } catch (e) {
      // bridge 还没就绪就丢掉这条——不能因为记日志把页面搞崩。
    }
  }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var start = Date.now();
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var method = (init && init.method) || (input && input.method) || 'GET';

      return origFetch.apply(this, arguments).then(function (res) {
        // 必须 clone——读掉原 response 的 body 会让页面自己读不到。
        res.clone().text().then(function (body) {
          post({ url: url, method: method, status: res.status,
                 ms: Date.now() - start, body: body.slice(0, MAX_BODY) });
        }).catch(function () {
          post({ url: url, method: method, status: res.status,
                 ms: Date.now() - start, body: '' });
        });
        return res;
      }).catch(function (err) {
        post({ url: url, method: method, status: -1,
               ms: Date.now() - start, body: String(err) });
        throw err;
      });
    };
  }

  var proto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
  if (proto) {
    var origOpen = proto.open;
    var origSend = proto.send;

    proto.open = function (method, url) {
      this.__pake = { method: method, url: url };
      return origOpen.apply(this, arguments);
    };

    proto.send = function () {
      var self = this;
      var start = Date.now();
      self.addEventListener('loadend', function () {
        var info = self.__pake || {};
        var body = '';
        try {
          if (self.responseType === '' || self.responseType === 'text') {
            body = String(self.responseText || '').slice(0, MAX_BODY);
          }
        } catch (e) { /* responseText 在某些 responseType 下会抛 */ }

        post({ url: info.url || '', method: info.method || 'GET',
               status: self.status, ms: Date.now() - start, body: body });
      });
      return origSend.apply(this, arguments);
    };
  }
})();
```

- [ ] **Step 7: 接进 webview_page.dart**

三处改动：

```dart
  final netLog = NetLog();
```

`_loadScripts` 里，在用户脚本**之前**插入 hook（必须 `AT_DOCUMENT_START`，晚了页面早期的请求就漏了）：

```dart
    scripts.insert(
      0,
      UserScript(
        groupName: '__pake_net_hook',
        source: await rootBundle.loadString('assets/net_hook.js'),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
```

`onWebViewCreated` 里挂 handler，并加 `onLoadResource` 回调：

```dart
      onWebViewCreated: (c) {
        _controller = c;
        c.addJavaScriptHandler(
          handlerName: 'pakeNet',
          callback: (args) {
            if (args.isEmpty || args.first is! Map) return;
            netLog.add(
              NetRecord.fromHandlerJson(args.first as Map<Object?, Object?>),
            );
          },
        );
      },
      onLoadResource: (_, resource) => netLog.add(NetRecord(
        url: resource.url?.toString() ?? '',
        method: 'GET',
        status: 0,
        durationMs: resource.duration?.round() ?? 0,
        at: DateTime.now(),
        source: NetSource.resource,
      )),
```

> `onLoadResource` 需要 `InAppWebViewSettings(useOnLoadResource: true)` —— Task 13 的 `_settings` 里已经开了。

- [ ] **Step 8: 实现 net_log_page.dart 并挂进 DebugDrawer**

沿用 `http_inspector` 的信息布局：列表 → 详情 → cURL 导出。

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'net_log.dart';
import 'net_record.dart';

class NetLogPage extends StatefulWidget {
  const NetLogPage({super.key, required this.log});

  final NetLog log;

  @override
  State<NetLogPage> createState() => _NetLogPageState();
}

class _NetLogPageState extends State<NetLogPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(widget.log.clear),
          ),
        ],
      ),
      body: StreamBuilder<void>(
        stream: widget.log.changes,
        builder: (context, _) {
          final records = widget.log.records;
          if (records.isEmpty) {
            return const Center(child: Text('No requests captured yet.'));
          }
          return ListView.separated(
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: records.length,
            itemBuilder: (context, i) => _tile(records[i]),
          );
        },
      ),
    );
  }

  Widget _tile(NetRecord r) => ListTile(
        dense: true,
        leading: Text(
          r.status <= 0 ? '—' : '${r.status}',
          style: TextStyle(
            color: r.status >= 400 || r.status < 0
                ? Colors.red
                : Colors.green.shade700,
          ),
        ),
        title: Text(r.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${r.method} · ${r.durationMs}ms · ${r.source.name}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _DetailPage(record: r)),
        ),
      );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.record});

  final NetRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy as cURL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: record.toCurl()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied as cURL')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText('${record.method} ${record.url}'),
          const SizedBox(height: 8),
          Text('Status ${record.status} · ${record.durationMs}ms'),
          if (record.source == NetSource.resource)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Captured via onLoadResource — body is not available for '
                'resource loads.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const Divider(height: 32),
          SelectableText(
            record.body ?? '(no body)',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
```

`DebugDrawer` 加一个 `netLog` 参数与一项：

```dart
          ListTile(
            title: const Text('View requests'),
            leading: const Icon(Icons.swap_vert),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NetLogPage(log: widget.netLog),
              ),
            ),
          ),
```

- [ ] **Step 9: 跑全量测试 + 真机验一次**

Run: `cd packages/pake_shell && flutter test && flutter run`
Expected: 测试全绿；加载任意站点后进设置 → View requests，能看到 document / 图片（`resource`）与页面 JS 发的 fetch（`js`，带 body）

- [ ] **Step 10: 提交**

```bash
git add packages/pake_shell
git commit -m "feat(shell): capture webview traffic via js hook and onLoadResource"
```

---

### Task 17: `pakem icon`

**Files:**
- Create: `packages/pake_cli/lib/src/commands/icon.dart`
- Modify: `packages/pake_cli/lib/src/materialize.dart`（物化时写图标）
- Modify: `packages/pake_cli/lib/src/runner.dart`
- Modify: `packages/pake_cli/pubspec.yaml`（加 `image: ^4.2.0`、`http: ^1.2.0`）
- Test: `packages/pake_cli/test/icon_test.dart`

**Interfaces:**
- Consumes: Task 4 `Output` / `PakeException` · Task 5 `Workspace`
- Produces:
  - `const Map<String, int> androidIconSizes` / `const Map<String, int> iosIconSizes`
  - `Future<List<int>> fetchIconBytes(String source, {http.Client? client})` —— 本地路径或 URL
  - `void writeAndroidIcons({required List<int> pngBytes, required String projectDir})`
  - `void writeIosIcons({required List<int> pngBytes, required String projectDir})`

- [ ] **Step 1: 写失败的测试**

`packages/pake_cli/test/icon_test.dart`：

```dart
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pake_cli/src/commands/icon.dart';
import 'package:pake_cli/src/output.dart';
import 'package:test/test.dart';

List<int> _png(int size) =>
    img.encodePng(img.Image(width: size, height: size));

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_icon'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads a local png file', () async {
    final path = '${tmp.path}/icon.png';
    File(path).writeAsBytesSync(_png(512));

    expect(await fetchIconBytes(path), isNotEmpty);
  });

  test('errors with exit code 1 for a missing local file', () {
    expect(
      () => fetchIconBytes('${tmp.path}/nope.png'),
      throwsA(isA<PakeException>()
          .having((e) => e.exitCode, 'exitCode', ExitCodes.config)),
    );
  });

  test('writes every android mipmap density', () {
    writeAndroidIcons(pngBytes: _png(512), projectDir: tmp.path);

    for (final entry in androidIconSizes.entries) {
      final file = File(
        '${tmp.path}/android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);

      final decoded = img.decodePng(file.readAsBytesSync())!;
      expect(decoded.width, entry.value);
    }
  });

  test('writes every ios AppIcon size', () {
    writeIosIcons(pngBytes: _png(1024), projectDir: tmp.path);

    for (final entry in iosIconSizes.entries) {
      final file = File(
        '${tmp.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);

      final decoded = img.decodePng(file.readAsBytesSync())!;
      expect(decoded.width, entry.value);
    }
  });

  test('rejects a non-image file with a config error', () {
    final path = '${tmp.path}/notanimage.png';
    File(path).writeAsStringSync('this is not a png');

    expect(
      () => writeAndroidIcons(
        pngBytes: File(path).readAsBytesSync(),
        projectDir: tmp.path,
      ),
      throwsA(isA<PakeException>()
          .having((e) => e.exitCode, 'exitCode', ExitCodes.config)),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/pake_cli && dart pub add image http && dart test test/icon_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pake_cli/src/commands/icon.dart'`

- [ ] **Step 3: 实现 icon.dart**

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../output.dart';

const androidIconSizes = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

const iosIconSizes = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// [source] 可以是本地路径，也可以是 http(s) URL（抓站点图标用）。
Future<List<int>> fetchIconBytes(String source, {http.Client? client}) async {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    final c = client ?? http.Client();
    try {
      final response = await c.get(Uri.parse(source));
      if (response.statusCode != 200) {
        throw PakeException(
          ExitCodes.config,
          'Could not download icon from $source (HTTP ${response.statusCode}).',
        );
      }
      return response.bodyBytes;
    } finally {
      if (client == null) c.close();
    }
  }

  final file = File(source);
  if (!file.existsSync()) {
    throw PakeException(ExitCodes.config, 'Icon file not found: $source');
  }
  return file.readAsBytesSync();
}

img.Image _decode(List<int> bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw PakeException(
      ExitCodes.config,
      'Could not decode the icon; expected a PNG, JPEG or WebP image.',
    );
  }
  return decoded;
}

void writeAndroidIcons({
  required List<int> pngBytes,
  required String projectDir,
}) {
  final source = _decode(pngBytes);
  for (final entry in androidIconSizes.entries) {
    final dir = Directory(
      p.join(projectDir, 'android/app/src/main/res', entry.key),
    )..createSync(recursive: true);

    File(p.join(dir.path, 'ic_launcher.png')).writeAsBytesSync(
      img.encodePng(
        img.copyResize(source, width: entry.value, height: entry.value),
      ),
    );
  }
}

void writeIosIcons({required List<int> pngBytes, required String projectDir}) {
  final source = _decode(pngBytes);
  final dir = Directory(
    p.join(projectDir, 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
  )..createSync(recursive: true);

  for (final entry in iosIconSizes.entries) {
    File(p.join(dir.path, entry.key)).writeAsBytesSync(
      img.encodePng(
        img.copyResize(source, width: entry.value, height: entry.value),
      ),
    );
  }
}

class IconCommand extends Command<int> {
  IconCommand(this._output) {
    argParser
      ..addOption('out', help: 'Directory to write the resized icon into.')
      ..addFlag('json', negatable: false);
  }

  final Output _output;

  @override
  String get name => 'icon';

  @override
  String get description =>
      'Fetch a site icon or convert a local image into app icon sets.';

  @override
  String get invocation => 'pakem icon <path|url>';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      throw PakeException(ExitCodes.config, 'pakem icon needs a path or URL.');
    }

    final bytes = await fetchIconBytes(args.rest.first);
    final out = args.option('out') ?? Directory.current.path;

    writeAndroidIcons(pngBytes: bytes, projectDir: out);
    writeIosIcons(pngBytes: bytes, projectDir: out);

    _output.success({'wroteIconsInto': out});
    return 0;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/pake_cli && dart test test/icon_test.dart`
Expected: PASS，5 个测试全绿

- [ ] **Step 5: 在物化流程里写图标**

`materializeConfig` 末尾加：

```dart
  final icon = config.iconPath;
  if (icon != null) {
    final bytes =
        File(p.isAbsolute(icon) ? icon : p.join(cwd, icon)).readAsBytesSync();
    writeAndroidIcons(pngBytes: bytes, projectDir: root);
    writeIosIcons(pngBytes: bytes, projectDir: root);
  }
```

（`materializeConfig` 是同步函数，`fetchIconBytes` 是异步的——所以这里只支持本地路径。远程 URL 走 `pakem icon` 单独命令，这个分工是刻意的。）

- [ ] **Step 6: 挂到 runner，跑全量测试，提交**

Run: `cd packages/pake_cli && dart test`
Expected: PASS

```bash
git add packages/pake_cli
git commit -m "feat(cli): add icon command and materialize app icons"
```

---

### Task 18: 端到端 smoke test 与 CI

**Files:**
- Create: `packages/pake_cli/test/smoke_test.dart`
- Create: `.github/workflows/build.yml`
- Create: `.github/workflows/test.yml`
- Create: `README.md`
- Create: `docs/manual-regression.md`

**Interfaces:**
- Consumes: 全部前序任务
- Produces: 无新 API

**CI 的设计约束（spec）：** workflow 只做三件事——装 Flutter → `dart pub global activate --source path packages/pake_cli` → `pakem build $URL --name $NAME --json`。逻辑零分叉，CI 与本地跑的是同一个 CLI。

- [ ] **Step 1: 写 smoke test**

`packages/pake_cli/test/smoke_test.dart`：

```dart
@Tags(['smoke'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// 真实构建一次 debug APK，断言产物存在。
///
/// 本地跑太慢（Android 冷构建数分钟），所以打 `smoke` tag，
/// 默认排除，只在 CI 跑：`dart test --tags smoke`。
void main() {
  test('pakem build produces an apk and json output', () async {
    final tmp = Directory.systemTemp.createTempSync('pakem_smoke');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final result = await Process.run(
      'dart',
      [
        'run',
        'bin/pakem.dart',
        'build',
        'https://example.com',
        '--name', 'Smoke',
        '--bundle-id', 'com.pake.smoke',
        '--platform', 'android',
        '--json',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());

    final json = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(json['ok'], isTrue);

    final artifacts = json['artifacts']! as List;
    expect(artifacts, isNotEmpty);
    expect(File(artifacts.first! as String).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
```

在 `packages/pake_cli/dart_test.yaml` 里默认排除它：

```yaml
tags:
  smoke:
    skip: "slow — run explicitly with: dart test --tags smoke"
```

- [ ] **Step 2: 确认 smoke test 默认被跳过**

Run: `cd packages/pake_cli && dart test`
Expected: smoke test 显示 skipped，其余全绿

- [ ] **Step 3: 写单测 workflow**

`.github/workflows/test.yml`：

```yaml
name: test

on:
  push:
    branches: [main]
  pull_request:

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.2'
          cache: true

      - name: pake_config
        working-directory: packages/pake_config
        run: dart pub get && dart test

      - name: pake_cli
        working-directory: packages/pake_cli
        run: dart pub get && dart test

      - name: pake_shell
        working-directory: packages/pake_shell
        run: flutter pub get && flutter test
```

- [ ] **Step 4: 写构建 workflow**

`.github/workflows/build.yml`：

```yaml
name: build

on:
  workflow_dispatch:
    inputs:
      url:
        description: 'URL to package'
        required: true
      name:
        description: 'App name'
        required: true
      bundle_id:
        description: 'Bundle id'
        required: true
        default: 'com.pake.app'

jobs:
  android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.2'
          cache: true

      # CI runner 每次是新环境，必然冷构建。缓存能缓解，
      # 但云构建始终慢于本地——这是物理限制，不是设计缺陷。
      - uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ runner.os }}-${{ hashFiles('packages/pake_shell/android/**/*.gradle*') }}

      - name: Install pakem
        run: dart pub global activate --source path packages/pake_cli

      - name: Build
        run: |
          pakem build "${{ inputs.url }}" \
            --name "${{ inputs.name }}" \
            --bundle-id "${{ inputs.bundle_id }}" \
            --platform android \
            --json

      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: ~/.pake/workspace/build/app/outputs/flutter-apk/*.apk

  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.2'
          cache: true
      - name: Smoke build
        working-directory: packages/pake_cli
        run: dart pub get && dart test --tags smoke
```

- [ ] **Step 5: 在 CI 上跑一次 smoke，确认真实构建能过**

```bash
gh workflow run build.yml -f url=https://example.com -f name=Smoke -f bundle_id=com.pake.smoke
gh run watch
```
Expected: android job 产出 APK 工件。**如果失败，把失败原因记进本任务再修**——这是整个计划里第一次真实构建，出问题很正常。

- [ ] **Step 6: 写手动回归清单**

`docs/manual-regression.md`：

```markdown
# 手动回归清单

需真机 + 真站点，自动化无法覆盖。每次发版执行。
以下四项来自 PakePlus-Android 的实际踩坑记录。

- [ ] **WASM streaming compile** —— 加载依赖 `WebAssembly.instantiateStreaming` 的站点。
      已有 shim 修复经验，若复发按同样思路在注入脚本里补 shim。
- [ ] **`blob:` / `data:` URL 下载** —— 触发一次页面内导出/下载，确认文件真的落盘。
- [ ] **输入法遮挡** —— 点页面底部输入框，确认键盘不遮挡（`windowSoftInputMode=adjustResize`）。
- [ ] **4K 视频播放** —— Pixel 8 已验证基线，确认不卡顿、不黑屏。

外加壳自身的四项：

- [ ] 左上角长按 1.5 秒能打开设置（在**网页白屏时**也要试一次）。
- [ ] 改 URL → 页面跳转；重启 app 后仍是新 URL。
- [ ] 切 UA → 页面 reload，站点识别为对应设备。
- [ ] 「重置」后回落到构建时的 URL 与 UA。
```

- [ ] **Step 7: 写 README**

`README.md`：

````markdown
# pake_mobile

把任意网页打包成 Android / iOS App。一套 Dart 代码出双端。

## 用法

```bash
dart pub global activate --source path packages/pake_cli

pakem init                                    # 生成 pake.json 模板
pakem build https://m.weibo.cn --name Weibo --bundle-id com.pake.weibo
pakem build https://m.weibo.cn --platform android,ios --team-id ABCDE12345 --profile "Pake Dev"
pakem icon https://m.weibo.cn/favicon.ico
pakem doctor
```

产物在 `~/.pake/workspace/build/`，构建日志在 `~/.pake/logs/`。

## 配置分两层

| | 构建期 `pake.json` | 运行期（设置页） |
|---|---|---|
| 内容 | app 名、bundle id、图标、版本号、初始 URL、系统权限 | 当前 URL、UA、注入脚本开关、缓存策略 |
| 谁写 | CLI | 设置页 |

改 UA 不需要重新构建。运行期层为空时回落构建期默认；「重置」= 清空运行期层。

## 设置页入口

网页左上角**长按 1.5 秒**。这个入口在网页白屏时同样可用——这是刻意设计，
否则一个错误的 URL 会让 app 变砖。

## 退出码

`1` 配置错误 · `2` 环境缺失 · `3` 构建失败。`--json` 模式下错误同样是 JSON。

## 开发

```bash
cd packages/pake_config && dart test
cd packages/pake_cli && dart test          # smoke test 默认跳过
cd packages/pake_shell && flutter test
```

发版前跑 [手动回归清单](docs/manual-regression.md)。
````

- [ ] **Step 8: 提交**

```bash
git add .github README.md docs/manual-regression.md packages/pake_cli
git commit -m "ci: add test and build workflows, smoke test and docs"
```

---

## 自审记录

**1. spec 覆盖检查**

| spec 章节 | 对应任务 |
|---|---|
| 单一代码库出双端 | Task 6 / 7 / 9 / 12 |
| 全屏 WebView | Task 13 |
| 切 URL / 切 UA / 脚本开关 / 清缓存 / 看日志 / 看请求 | Task 15 / 16 |
| 运行时可调配置 | Task 12 |
| CLI 为唯一入口 | Task 4 / 9 / 11 / 17 |
| 配置分两层 | Task 3（键）/ Task 12（读写） |
| EscapeHatch | Task 14 |
| 注入机制 + try/catch | Task 8 / 13 |
| 网络检查 | Task 16 |
| 固定 workspace + 锁 | Task 5 / 10 |
| iOS 签名 | Task 7 / 11 |
| 错误处理（CLI 三级退出码 / 运行时错误页） | Task 4 / 9 / 13 |
| 测试策略四层 | Task 1–3（config）/ 6–8（golden）/ 12–16（widget）/ 18（smoke） |
| 手动回归清单 | Task 18 |
| CI | Task 18 |

**未覆盖项：** spec「运行期配置」表里列了「全屏」「手势」「缓存策略」「日志级别」三项，本计划只在 `RuntimeKeys` 里预留了 `fullscreen` 与 `logLevel` 常量，未做设置页 UI。判断为 YAGNI——全屏本就是默认行为，日志级别在设置页拨动的价值低于其实现成本。**如果需要，另开一个小任务，不要塞进现有任务。**

**2. 类型一致性检查**

- `Workspace.withLock` 在 Task 5 定义为同步，Task 9 需要异步。已在 Task 9 Step 6 显式标注要回改，并要求同步更新 Task 5 的测试。这是全计划唯一的回改点。
- `Output.success` 接受 `Map<String, Object?>`，Task 4 / 9 / 11 / 17 的调用一致。
- `ProcessRunner.run` 签名在 Task 9 定义，Task 11 的 `checkIosSigning` / `loadInstalledProfiles` 与 doctor 均按此调用。
- `materializeScript` 返回 `MaterializedScript`（Task 8），Task 10 消费其 `id` / `kind` / `source` 三个字段，一致。
- `RuntimeConfig` 的 `enabledScripts` 返回 `Set<String>`，Task 13 / 15 均按 Set 用。
- `NetRecord` 的 `source` 字段在 Task 16 定义并在 `NetLogPage` 中消费。

**3. 已知需要在实现时验证的三处**

- `get_storage 2.1.1` 与 Flutter 3.41 的兼容性（Task 12 Step 2 显式设了检查点，冲突就停下报告）。
- `logger_utils` 的 file sink 实际落盘目录（Task 15 Step 4 标注了 `Directory.current` 是占位）。
- CI 上第一次真实构建（Task 18 Step 5）。









