import 'package:path/path.dart' as p;

import 'config.dart';

/// 一个注入脚本的运行期标识。
///
/// 三个包必须都走这个函数，否则整条开关链路会静默失效：CLI 曾经用
/// `basenameWithoutExtension` 命名物化产物和 `index.json` 的 `id`，而壳
/// 拿 `pake.json` 里的**原始路径**当默认启用集合去比对，
/// `{'hide-ads.js'}.contains('hide-ads')` 永远为 false——所有注入脚本
/// 从来没有生效过，而且每个包的测试都是绿的。
///
/// 语义就是「去掉目录和扩展名」：`scripts/theme.css` → `theme`。
String scriptIdFor(String path) => p.basenameWithoutExtension(path);

/// 运行期层没存过东西时，壳启用哪些脚本：构建时特意打包进来的全开。
///
/// 逻辑本属于壳，放这里是为了让 `pake_cli` 的 contract test 能调到**壳真正
/// 在用的那个函数**：`pake_cli` 是纯 Dart 包，依赖不了 Flutter 包
/// `pake_shell`，测试里照抄一遍公式就只能证明抄得对，证明不了两边一致。
Set<String> defaultEnabledScripts(PakeConfig config) =>
    config.injectScripts.map(scriptIdFor).toSet();
