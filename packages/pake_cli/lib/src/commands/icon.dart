import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../output.dart';

const androidIconSizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

const iosIconSizes = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// [source] 可以是本地路径，也可以是 http(s) URL（抓站点图标用）。
Future<List<int>> fetchIconBytes(String source, {http.Client? client}) async {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    final c = client ?? http.Client();
    try {
      final response = await c.get(Uri.parse(source));
      if (response.statusCode != 200) {
        throw PakeException(
          ExitCodes.config,
          'Could not download icon from $source (HTTP ${response.statusCode}).',
        );
      }
      return response.bodyBytes;
    } finally {
      if (client == null) c.close();
    }
  }

  final file = File(source);
  if (!file.existsSync()) {
    throw PakeException(ExitCodes.config, 'Icon file not found: $source');
  }
  return file.readAsBytesSync();
}

img.Image _decode(List<int> bytes) {
  final decoded = img.decodeImage(Uint8List.fromList(bytes));
  if (decoded == null) {
    throw PakeException(
      ExitCodes.config,
      'Could not decode the icon; expected a PNG, JPEG or WebP image.',
    );
  }
  return decoded;
}

void writeAndroidIcons({
  required List<int> pngBytes,
  required String projectDir,
}) {
  final source = _decode(pngBytes);
  for (final entry in androidIconSizes.entries) {
    final dir = Directory(
      p.join(projectDir, 'android/app/src/main/res', 'mipmap-${entry.key}'),
    )..createSync(recursive: true);

    _writeBytesIfChanged(
      File(p.join(dir.path, 'ic_launcher.png')),
      img.encodePng(
        img.copyResize(source, width: entry.value, height: entry.value),
      ),
    );
  }
}

void writeIosIcons({required List<int> pngBytes, required String projectDir}) {
  final source = _decode(pngBytes);
  final dir = Directory(
    p.join(projectDir, 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
  )..createSync(recursive: true);

  for (final entry in iosIconSizes.entries) {
    _writeBytesIfChanged(
      File(p.join(dir.path, entry.key)),
      img.encodePng(
        img.copyResize(source, width: entry.value, height: entry.value),
      ),
    );
  }
}

/// 只在字节真的变了才写——跟 `materialize.dart` 里字符串版的
/// `_writeIfChanged` 是同一个道理：图标文件无谓的 mtime 变化会让
/// Gradle / Xcode 的增量判定失效，固定 workspace 的增量缓存就白搭了。
/// `package:image` 的 PNG 编码器是像素数据的纯函数，不带时间戳或随机数，
/// 同一份源图重新编码出的字节可以放心逐字节比较。
void _writeBytesIfChanged(File file, List<int> bytes) {
  if (file.existsSync() && _bytesEqual(file.readAsBytesSync(), bytes)) {
    return;
  }
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class IconCommand extends Command<int> {
  IconCommand(this._output) {
    // 顶层 CommandRunner 已经挂了全局 --json，这里不重复加。
    argParser.addOption(
      'out',
      help: 'Directory to write the resized icon into.',
    );
  }

  final Output _output;

  @override
  String get name => 'icon';

  @override
  String get description =>
      'Fetch a site icon or convert a local image into app icon sets.';

  @override
  String get invocation => 'pakem icon <path|url>';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      throw PakeException(ExitCodes.config, 'pakem icon needs a path or URL.');
    }

    final bytes = await fetchIconBytes(args.rest.first);
    final out = args.option('out') ?? Directory.current.path;

    writeAndroidIcons(pngBytes: bytes, projectDir: out);
    writeIosIcons(pngBytes: bytes, projectDir: out);

    _output.success({'wroteIconsInto': out});
    return 0;
  }
}
