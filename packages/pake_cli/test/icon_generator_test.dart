import 'package:image/image.dart' as img;
import 'package:pake_cli/src/icon_generator.dart';
import 'package:test/test.dart';

void main() {
  group('glyphFor', () {
    test('takes the first letter of an ascii name, uppercased', () {
      expect(glyphFor(name: 'YouTube', bundleId: 'com.pake.youtube'), 'Y');
      expect(glyphFor(name: 'dadatu', bundleId: 'com.pake.dadatu'), 'D');
    });

    test('a leading digit is a fine glyph', () {
      expect(glyphFor(name: '4KVM', bundleId: 'com.pake.fourkvm'), '4');
    });

    test('skips past non-ascii to the first character it can draw', () {
      // 内置的 Arial 位图字体只有 ASCII，`影` 根本没有字形。
      expect(glyphFor(name: '4K影视', bundleId: 'com.pake.fourkvm'), '4');
    });

    test('falls back to the bundle id when the name is all non-ascii', () {
      // bundleId 永远是 ASCII，所以这条链一定能落地。
      expect(glyphFor(name: '影视大全', bundleId: 'com.pake.dadatu'), 'D');
      expect(glyphFor(name: '微博', bundleId: 'com.pake.weibo'), 'W');
    });

    test('gives up on a placeholder rather than throwing', () {
      // 两头都挑不出字符是配置坏掉了，但生成图标不该是构建炸掉的地方。
      expect(glyphFor(name: '微博', bundleId: '。。'), '?');
    });
  });

  group('generateIcon', () {
    test('is a decodable png of the size asked for', () {
      final decoded = img.decodePng(
        generateIcon(name: '4KVM', bundleId: 'com.pake.fourkvm', size: 256),
      );

      expect(decoded, isNotNull);
      expect(decoded!.width, 256);
      expect(decoded.height, 256);
    });

    test('draws the glyph in white on a solid background', () {
      final icon = img.decodePng(
        generateIcon(name: 'DADATU', bundleId: 'com.pake.dadatu', size: 256),
      )!;

      // 角落是底色，中心落在字形上——`D` 的中心是空的，所以取字形左竖那一列。
      final corner = icon.getPixel(4, 4);
      expect(corner.r == 255 && corner.g == 255 && corner.b == 255, isFalse);
      final onStroke = icon.getPixel(85, 128);
      expect(onStroke.r, 255);
      expect(onStroke.g, 255);
      expect(onStroke.b, 255);
    });

    test('same app in, same bytes out', () {
      // 每次重新构建都换个颜色的话，用户会以为装错了 app。
      final first = generateIcon(name: '4KVM', bundleId: 'com.pake.fourkvm');
      final second = generateIcon(name: '4KVM', bundleId: 'com.pake.fourkvm');

      expect(first, orderedEquals(second));
    });

    test('different names get different colours', () {
      final a = img.decodePng(
        generateIcon(name: '4KVM', bundleId: 'com.pake.fourkvm', size: 64),
      )!;
      final b = img.decodePng(
        generateIcon(name: 'DADATU', bundleId: 'com.pake.dadatu', size: 64),
      )!;

      final one = a.getPixel(2, 2);
      final two = b.getPixel(2, 2);
      expect(
        [one.r, one.g, one.b],
        isNot(orderedEquals([two.r, two.g, two.b])),
        reason:
            'a screen full of identical tiles is no better than a screen '
            'full of identical globes',
      );
    });

    test('a wide glyph still fits inside the tile', () {
      // W 和 M 按高度缩会顶到左右边，得再按宽度收一次。
      final icon = img.decodePng(
        generateIcon(name: 'WWW', bundleId: 'com.pake.www', size: 256),
      )!;

      for (var y = 0; y < 256; y++) {
        final left = icon.getPixel(2, y);
        expect(
          left.r == 255 && left.g == 255 && left.b == 255,
          isFalse,
          reason: 'the glyph runs off the left edge at y=$y',
        );
      }
    });
  });
}
