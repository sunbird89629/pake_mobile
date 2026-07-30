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
