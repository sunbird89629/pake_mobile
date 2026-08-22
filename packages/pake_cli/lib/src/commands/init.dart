import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../output.dart';

/// 模板内容独立成函数，好让测试不经过 CommandRunner 直接验。
void writeInitTemplate(String directory) {
  final file = File(p.join(directory, 'pake.json'));
  if (file.existsSync()) {
    throw PakeException(
      ExitCodes.config,
      'pake.json already exists at ${file.path}; refusing to overwrite it.',
    );
  }

  const template = {
    'name': 'My App',
    'url': 'https://example.com',
    'bundleId': 'com.example.myapp',
    'version': '1.0.0',
    'injectScripts': <String>[],
    'permissions': <String>[],
  };

  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(template)}\n',
  );
}

class InitCommand extends Command<int> {
  InitCommand(this._output);

  final Output _output;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Generate a pake.json template in the current directory.';

  @override
  int run() {
    writeInitTemplate(Directory.current.path);
    _output.success({'created': p.join(Directory.current.path, 'pake.json')});
    return 0;
  }
}
