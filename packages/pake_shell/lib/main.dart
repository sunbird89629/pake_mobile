import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/runtime_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `initLogging` 不传 `logsDir` 就压根不写文件（只有控制台输出），真机上
  // 根本看不到——必须显式给一个真实目录，并把同一个目录传给 LogPage 读。
  final logsDir = '${(await getApplicationDocumentsDirectory()).path}/logs';
  initLogging(logsDir: logsDir, filePrefix: 'pake');
  // debug_sheet 的输入历史也写这个默认容器，必须在 runApp 前初始化。
  await GetStorage.init();

  runApp(PakeApp(config: await RuntimeConfig.load(), logsDir: logsDir));
}
