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
