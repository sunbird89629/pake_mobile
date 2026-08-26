import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pake_cli/src/commands/icon.dart';
import 'package:pake_cli/src/output.dart';
import 'package:test/test.dart';

List<int> _png(int size) => img.encodePng(img.Image(width: size, height: size));

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pakem_icon'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads a local png file', () async {
    final path = '${tmp.path}/icon.png';
    File(path).writeAsBytesSync(_png(512));

    expect(await fetchIconBytes(path), isNotEmpty);
  });

  // 自动发现下载成功不等于拿到了图片：x.com 对
  // `/apple-touch-icon.png` 返回 200 + 287KB 的首页 HTML，而不是 404。
  // 这一层挡不住的话，解码要到 materializeConfig 里才炸，那时已经出了
  // build 命令里那个 try——自动发现猜错一次，整个构建就失败。
  group('canDecodeIcon', () {
    test('rejects the HTML an SPA serves in place of a 404', () {
      final html =
          '<!DOCTYPE html><html dir="ltr" lang="en"><body></body></html>';
      expect(canDecodeIcon(html.codeUnits), isFalse);
    });

    test('accepts a real png', () {
      expect(canDecodeIcon(_png(512)), isTrue);
    });

    test('rejects empty bytes', () {
      expect(canDecodeIcon(const []), isFalse);
    });
  });

  test('errors with exit code 1 for a missing local file', () {
    expect(
      () => fetchIconBytes('${tmp.path}/nope.png'),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.config,
        ),
      ),
    );
  });

  test('writes every android mipmap density', () {
    writeAndroidIcons(pngBytes: _png(512), projectDir: tmp.path);

    for (final entry in androidIconSizes.entries) {
      final file = File(
        '${tmp.path}/android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);

      final decoded = img.decodePng(file.readAsBytesSync())!;
      expect(decoded.width, entry.value);
    }
  });

  test('writes every ios AppIcon size', () {
    writeIosIcons(pngBytes: _png(1024), projectDir: tmp.path);

    for (final entry in iosIconSizes.entries) {
      final file = File(
        '${tmp.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);

      final decoded = img.decodePng(file.readAsBytesSync())!;
      expect(decoded.width, entry.value);
    }
  });

  // 空文件走的是另一条路：decodeImage 探测 magic number 时直接越界抛
  // RangeError，不是返回 null。不接住的话用户看到的是解码器内部的类型
  // 错误，而不是「这不是一张图」。
  test(
    'rejects an empty file with the same config error, not a RangeError',
    () {
      expect(
        () => writeAndroidIcons(pngBytes: const [], projectDir: tmp.path),
        throwsA(
          isA<PakeException>().having(
            (e) => e.exitCode,
            'exitCode',
            ExitCodes.config,
          ),
        ),
      );
    },
  );

  test('rejects a non-image file with a config error', () {
    final path = '${tmp.path}/notanimage.png';
    File(path).writeAsStringSync('this is not a png');

    expect(
      () => writeAndroidIcons(
        pngBytes: File(path).readAsBytesSync(),
        projectDir: tmp.path,
      ),
      throwsA(
        isA<PakeException>().having(
          (e) => e.exitCode,
          'exitCode',
          ExitCodes.config,
        ),
      ),
    );
  });
}
