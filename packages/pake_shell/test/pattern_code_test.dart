import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/lock/pattern_code.dart';

void main() {
  group('encodePattern', () {
    test('separates cells so multi-digit indices cannot collide', () {
      // 直接拼数字的话 [1,12] 和 [11,2] 都是 "112"，两个不同图案会撞成
      // 同一个哈希。分隔符就是为了堵这个。
      expect(encodePattern([1, 12]), isNot(encodePattern([11, 2])));
    });
  });

  group('hashPattern', () {
    test('is stable for the same pattern', () {
      expect(hashPattern([0, 1, 2, 5]), hashPattern([0, 1, 2, 5]));
    });

    test('is order sensitive', () {
      // 图案是有向的：同样四个点，反着画是另一个图案。
      expect(hashPattern([0, 1, 2, 5]), isNot(hashPattern([5, 2, 1, 0])));
    });

    test('never returns the pattern itself', () {
      // 这条是这次改动的全部意义：存储里不能再出现明文。
      final hash = hashPattern([0, 1, 2, 5]);
      expect(hash, isNot(contains('0-1-2-5')));
      expect(hash.length, 64);
    });
  });

  group('validatePattern', () {
    test('accepts a matching pattern of the minimum length', () {
      expect(validatePattern([0, 1, 2, 5], [0, 1, 2, 5]), isNull);
    });

    test('rejects a pattern that is too short', () {
      expect(validatePattern([0, 1, 2], [0, 1, 2]), isNotNull);
    });

    test('rejects a mismatched confirmation', () {
      expect(validatePattern([0, 1, 2, 5], [0, 1, 2, 4]), isNotNull);
    });

    test('rejects the same dots drawn in a different order', () {
      expect(validatePattern([0, 1, 2, 5], [5, 2, 1, 0]), isNotNull);
    });

    test('checks length before matching', () {
      // 两笔都太短但一模一样时，不能因为「匹配」就放行。
      expect(validatePattern([0, 1], [0, 1]), isNotNull);
    });
  });
}
