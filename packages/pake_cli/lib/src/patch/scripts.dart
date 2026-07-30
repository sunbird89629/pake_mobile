import 'package:path/path.dart' as p;

enum ScriptKind { js, css }

/// 一个已物化的注入脚本：`id` 是运行期开关的键，`source` 是最终注入
/// WebView 的 JS 文本（CSS 已被包成插 `<style>` 的 JS）。
class MaterializedScript {
  const MaterializedScript({
    required this.id,
    required this.kind,
    required this.source,
  });

  final String id;
  final ScriptKind kind;
  final String source;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'source': source,
  };
}

/// 把源文件变成可直接注入的 JS。
///
/// 一律包 try/catch —— spec 要求单个脚本抛异常不得导致整页失效，
/// 而 `UserScript` 是顺序注入的，一个异常会中断后面的脚本。
MaterializedScript materializeScript({
  required String path,
  required String content,
}) {
  final ext = p.extension(path).toLowerCase();
  final id = p.basenameWithoutExtension(path);

  final kind = switch (ext) {
    '.js' => ScriptKind.js,
    '.css' => ScriptKind.css,
    _ => throw ArgumentError.value(
      path,
      'path',
      'Only .js and .css can be injected',
    ),
  };

  final body = switch (kind) {
    ScriptKind.js => content,
    ScriptKind.css =>
      '''
  var style = document.createElement('style');
  style.type = 'text/css';
  style.appendChild(document.createTextNode(`${_escapeTemplate(content)}`));
  (document.head || document.documentElement).appendChild(style);''',
  };

  return MaterializedScript(
    id: id,
    kind: kind,
    source:
        '''
(function () {
try {
$body
} catch (e) {
  console.error('[pake:$id]', e && e.message ? e.message : e);
}
})();
''',
  );
}

/// CSS 内容嵌进 JS 模板字符串，必须转义反引号与 `\${`，
/// 否则恶意或手滑的 CSS 能逃出模板执行任意代码。
String _escapeTemplate(String css) => css
    .replaceAll(r'\', r'\\')
    .replaceAll('`', r'\`')
    .replaceAll(r'${', r'\${');
