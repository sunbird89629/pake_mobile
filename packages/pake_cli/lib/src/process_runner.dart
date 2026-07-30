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
  }) => Process.run(executable, args, workingDirectory: workingDirectory);
}
