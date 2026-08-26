import 'dart:typed_data';

import 'package:image/image.dart';

/// 站点一张能用的图标都没有时，按 app 名生成一个。
///
/// 结果是纯色底 + 一个白色大字符，形状上跟通讯录头像、Gmail 的联系人头像是
/// 同一类东西。它替掉的是模板里那个默认地球仪——那玩意儿装一屏就分不出谁是
/// 谁，而这里至少颜色和字母都跟着 app 走。
///
/// 同样的输入永远生成同样的字节：哈希是自己算的，没用 `String.hashCode`
/// （那个值不保证跨运行、跨 Dart 版本稳定），否则同一个 app 每次重新构建都
/// 可能换个颜色。

/// 压白字还算好看的一组底色。都是中深度的饱和色——浅色配白字看不清，而这个
/// 图标总共就一个字符可看。
const _palette = [
  0x2d6aa8, // 蓝
  0x8e44ad, // 紫
  0xc0392b, // 红
  0x1e8449, // 绿
  0xd35400, // 橙
  0x16a085, // 青
  0x2c3e50, // 藏青
  0x9a7d0a, // 暗金
];

Color _rgb(int hex) =>
    ColorRgba8((hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff, 255);

/// 画在图标上的那个字符。
///
/// 内置的是 Arial 位图字体，只有 ASCII——中文名字直接查不到字形。所以逐级往
/// 下找：名字里第一个 ASCII 字母或数字（`4K影视` → `4`），一个都没有就用
/// bundleId 末段的（`com.pake.dadatu` → `D`）。bundleId 永远是 ASCII，这条
/// 链一定能落地。
String glyphFor({required String name, required String bundleId}) =>
    _firstAscii(name) ?? _firstAscii(bundleId.split('.').last) ?? '?';

String? _firstAscii(String text) {
  for (final rune in text.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isUpper = rune >= 0x41 && rune <= 0x5a;
    final isLower = rune >= 0x61 && rune <= 0x7a;
    if (isDigit || isUpper || isLower) {
      return String.fromCharCode(rune).toUpperCase();
    }
  }
  return null;
}

/// 名字决定底色。改名会换颜色，这是「按名字生成」的应有之义。
int _paletteIndex(String seed) {
  // FNV-1a 的 32 位变体，够散且好复现。
  var hash = 0x811c9dc5;
  for (final rune in seed.runes) {
    hash = (hash ^ rune) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % _palette.length;
}

/// 生成一张 [size]×[size] 的 PNG。
Uint8List generateIcon({
  required String name,
  required String bundleId,
  int size = 512,
}) {
  final canvas = Image(width: size, height: size, numChannels: 4);
  fill(canvas, color: _rgb(_palette[_paletteIndex(name)]));

  final glyph = _renderGlyph(glyphFor(name: name, bundleId: bundleId));
  if (glyph != null) {
    // 先按高度缩到画布的 54%，太宽的字符（W、M）再按宽度收一次，免得顶边。
    var scaled = copyResize(
      glyph,
      height: (size * 0.54).round(),
      interpolation: Interpolation.nearest,
    );
    final maxWidth = (size * 0.66).round();
    if (scaled.width > maxWidth) {
      scaled = copyResize(
        glyph,
        width: maxWidth,
        interpolation: Interpolation.nearest,
      );
    }
    scaled = _smooth(scaled, (size * 0.012).round().clamp(1, 32));
    compositeImage(
      canvas,
      scaled,
      dstX: (size - scaled.width) ~/ 2,
      dstY: (size - scaled.height) ~/ 2,
    );
  }

  return encodePng(canvas);
}

/// 把字符画出来，裁成紧贴字形的一小块。
///
/// 不去算字体的基线和 `yOffset`：画在一张透明大画布上再按透明度裁，得到的就
/// 是字形本身的包围盒，居中时不用关心 `4` 和 `Y` 的度量差别。
Image? _renderGlyph(String character) {
  const canvasSize = 128;
  final small = Image(width: canvasSize, height: canvasSize, numChannels: 4);
  fill(small, color: ColorRgba8(0, 0, 0, 0));
  drawString(
    small,
    character,
    font: arial48,
    x: 30,
    y: 30,
    color: ColorRgba8(255, 255, 255, 255),
  );

  final box = findTrim(small, mode: TrimMode.transparent);
  if (box[2] <= 0 || box[3] <= 0) return null;
  return copyCrop(small, x: box[0], y: box[1], width: box[2], height: box[3]);
}

/// 磨掉最近邻放大留下的台阶。
///
/// 48px 的位图字形放大 6 倍，边缘是一格一格的。模糊一道再按透明度切回硬边，
/// 台阶就被抹平了；阈值取得比半透明的中点低，顺带把笔画撑粗一点——Arial
/// 常规体的笔画搁在图标上偏细。
///
/// 模糊前先四周留白：直接糊紧贴字形的那块，撑出去的部分会被边界裁掉。
Image _smooth(Image glyph, int radius) {
  final pad = radius * 2;
  final padded = Image(
    width: glyph.width + pad * 2,
    height: glyph.height + pad * 2,
    numChannels: 4,
  );
  fill(padded, color: ColorRgba8(0, 0, 0, 0));
  compositeImage(padded, glyph, dstX: pad, dstY: pad);

  final blurred = gaussianBlur(padded, radius: radius);
  for (final pixel in blurred) {
    pixel
      ..a = pixel.a >= 70 ? 255 : 0
      ..r = 255
      ..g = 255
      ..b = 255;
  }

  final box = findTrim(blurred, mode: TrimMode.transparent);
  if (box[2] <= 0 || box[3] <= 0) return glyph;
  return copyCrop(blurred, x: box[0], y: box[1], width: box[2], height: box[3]);
}
