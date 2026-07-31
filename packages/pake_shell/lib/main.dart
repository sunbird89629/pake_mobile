import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'src/runtime_config.dart';

/// 占位 main：只负责在 `runApp` 之前把 `GetStorage` 初始化好，
/// 并把两层配置读出来验证能跑通。真正的 WebView 界面是 Task 13 的活。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  final config = await RuntimeConfig.load();
  runApp(PakeShellPlaceholder(config: config));
}

class PakeShellPlaceholder extends StatelessWidget {
  const PakeShellPlaceholder({super.key, required this.config});

  final RuntimeConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pake_shell',
      home: Scaffold(body: Center(child: Text('pake_shell: ${config.url}'))),
    );
  }
}
