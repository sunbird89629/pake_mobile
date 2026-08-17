// 开发期把注入脚本物化进 assets/scripts/，让直接跑 lib/main.dart 也能调试
// 脚本注入，不必走完整的 `pakem build`。
//
//   cd packages/pake_shell
//   dart run tool/dev_scripts.dart
//
// 脚本源写在 assets/pake.json 的 injectScripts 里，路径相对本目录，例如
// `["dev_scripts/hide-ads.js"]`。改完脚本重跑一次本命令，再 hot restart（R）
// 即可生效——rootBundle 的缓存会在 reassemble 时自动清掉，不用手动 evict。
//
// dev_scripts/ 与物化产物都已 gitignore：它们是各人本机的调试内容，而
// assets/scripts/ 在真实构建里由 materializeConfig 重写（syncTemplate 绕开
// 这棵子树），所以这里放什么都不会跟着用户构建的 app 走。

import 'dart:convert';
import 'dart:io';

import 'package:pake_cli/pake_cli.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

void main() {
  final root = Directory.current.path;
  final configFile = File(p.join(root, 'assets/pake.json'));
  if (!configFile.existsSync()) {
    stderr.writeln(
      'assets/pake.json not found — run this from packages/pake_shell/',
    );
    exit(ExitCodes.config);
  }

  final config = PakeConfig.fromJson(
    jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>,
  );

  try {
    materializeScriptsInto(
      config: config,
      outDir: Directory(p.join(root, 'assets/scripts')),
      cwd: root,
      // .gitkeep 是签入仓库的，不能被当成上一次构建的残留删掉。
      preserve: const {'.gitkeep'},
    );
  } on PakeException catch (e) {
    stderr.writeln(e.message);
    exit(e.exitCode);
  }

  final ids = config.injectScripts.map(scriptIdFor).toList();
  if (ids.isEmpty) {
    stdout.writeln(
      'assets/pake.json 的 injectScripts 是空的，没有脚本可物化。\n'
      '把调试脚本放进 dev_scripts/，再把路径填进 injectScripts。',
    );
    return;
  }
  stdout.writeln('materialized ${ids.length}: ${ids.join(', ')}');
  // 壳只在运行期没存过 enabledScripts 时才回落到「全开」。设置页拨过一次
  // 开关后，新加的脚本 id 不在存量集合里，加了也不会注入——见
  // RuntimeConfig.enabledScripts。
  stdout.writeln('新增脚本没生效的话，去设置页 Reset 一次再 hot restart。');
}
