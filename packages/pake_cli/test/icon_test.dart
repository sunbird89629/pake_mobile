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
