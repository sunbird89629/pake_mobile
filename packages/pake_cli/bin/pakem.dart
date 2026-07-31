import 'dart:io';

import 'package:pake_cli/src/output.dart';
import 'package:pake_cli/src/runner.dart';

Future<void> main(List<String> args) async {
  // --json 要在解析命令之前就知道，否则出错信息的格式会不一致。
  final output = Output(json: args.contains('--json'));

  // 退出码的分级映射在 `runCli` 里，那里能被单测覆盖；这里只负责 exit()。
  exit(await runCli(args, output));
}
