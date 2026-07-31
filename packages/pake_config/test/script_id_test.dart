import 'package:pake_config/pake_config.dart';
import 'package:test/test.dart';

void main() {
  group('scriptIdFor', () {
    test('strips the directory and the extension', () {
      expect(scriptIdFor('hide-ads.js'), 'hide-ads');
      expect(scriptIdFor('scripts/theme.css'), 'theme');
      expect(scriptIdFor('/abs/dir/fix-video.js'), 'fix-video');
    });

    test('a .js and a .css of the same stem collide, which is why '
        'validateConfig has to reject that pair', () {
      expect(scriptIdFor('a/theme.js'), scriptIdFor('b/theme.css'));
    });

    test('keeps dots inside the stem', () {
      expect(scriptIdFor('my.fix.v2.js'), 'my.fix.v2');
    });
  });
}
