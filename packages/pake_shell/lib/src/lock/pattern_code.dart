import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 图案至少要连几个点。
///
/// 4 是 Android 系统锁的下限，抄它：3 个点的图案组合太少，而且人画三点时
/// 几乎必然是一条直线，肩窥一眼就记住了。
const minPatternLength = 4;

/// 把图案序列化成可哈希的字符串。
///
/// 用 `-` 连接而不是直接拼数字：格子数超过 10 之后 `[1,12]` 和 `[11,2]`
/// 拼出来都是 `112`，两个不同图案会碰撞成同一个哈希。
String encodePattern(List<int> cells) => cells.join('-');

/// 图案的 SHA-256 十六进制摘要。
///
/// 不加盐：威胁模型是「别人拿起我的手机」，不是取证分析——加盐防的是彩虹表，
/// 而拿到设备的人本来就能直接暴力枚举全部图案（3×3 的合法图案不到 40 万种，
/// 本地算完是秒级）。加盐只会让人误以为这里的安全性比实际更高。
/// 相比明文存 PIN 的旧方案，哈希真正换来的是：随手看一眼存储文件不会直接
/// 泄露密码。
String hashPattern(List<int> cells) =>
    sha256.convert(utf8.encode(encodePattern(cells))).toString();

/// 校验一对图案输入。通过返回 `null`，否则返回给用户看的原因。
String? validatePattern(List<int> pattern, List<int> confirm) {
  if (pattern.length < minPatternLength) {
    return 'Connect at least $minPatternLength dots.';
  }
  if (!_sameOrder(pattern, confirm)) return 'The two patterns do not match.';
  return null;
}

/// 顺序敏感的相等比较——图案是有向的，`1-2-3` 和 `3-2-1` 不是同一个。
bool _sameOrder(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
