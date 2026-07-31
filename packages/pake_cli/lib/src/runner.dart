import 'package:args/command_runner.dart';

import 'commands/build.dart';
import 'commands/doctor.dart';
import 'commands/icon.dart';
import 'commands/init.dart';
import 'output.dart';

CommandRunner<int> buildRunner(Output output) {
  return CommandRunner<int>('pakem', 'Build any web page into a mobile app.')
    ..argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit machine-readable JSON output instead of human-readable text.',
    )
    ..addCommand(InitCommand(output))
    ..addCommand(BuildCommand(output))
    ..addCommand(DoctorCommand(output))
    ..addCommand(IconCommand(output));
}

/// 跑一次 CLI，返回退出码。
///
/// 映射逻辑放在 lib 里而不是 `bin/pakem.dart`：`main()` 里 `exit()` 之前的
/// 分支在进程内测不到，而退出码分级正是 agent 编程处置的依据。
Future<int> runCli(List<String> args, Output output) async {
  try {
    return await buildRunner(output).run(args) ?? 0;
  } on PakeException catch (e) {
    output.failure(e);
    return e.exitCode;
  } on UsageException catch (e) {
    // 子命令拼错、flag 不认识——这是用法/配置错（1），不是构建失败（3）。
    // 分级存在的意义就是让 agent 能按码分支；把「你敲错了命令」报成
    // 「构建炸了」，这套分级就白设了。
    output.failure(PakeException(ExitCodes.config, e.message));
    return ExitCodes.config;
  } catch (e) {
    output.failure(PakeException(ExitCodes.build, e.toString()));
    return ExitCodes.build;
  }
}
