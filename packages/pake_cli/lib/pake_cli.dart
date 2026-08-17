/// `pake_cli` 里可供其它包复用的那一小块。
///
/// 刻意只导出脚本物化：`pake_shell` 的开发期工具要用它，别的都是 CLI 内部
/// 实现，暴露出去只会让 workspace 的构建流程被外部依赖住。
library;

export 'src/materialize.dart' show materializeScriptsInto;
export 'src/output.dart' show ExitCodes, PakeException;
export 'src/patch/scripts.dart' show MaterializedScript, ScriptKind;
