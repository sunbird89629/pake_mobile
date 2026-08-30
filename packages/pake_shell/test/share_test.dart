import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/share.dart';

void main() {
  group('shareTextFor', () {
    test('name, description and url each get their own line', () {
      expect(
        shareTextFor(
          name: '4KVM',
          description: '4K 高清影视，电影美剧日更，打开即看。',
          url: 'https://github.com/sunbird89629/pake_mobile/releases/tag/fourkvm-v0.1.0',
        ),
        '4KVM\n4K 高清影视，电影美剧日更，打开即看。\n'
        'https://github.com/sunbird89629/pake_mobile/releases/tag/fourkvm-v0.1.0',
      );
    });

    test('skips the description line when it is absent or blank', () {
      expect(
        shareTextFor(name: '4KVM', url: 'https://example.com'),
        '4KVM\nhttps://example.com',
      );
      expect(
        shareTextFor(name: '4KVM', description: '  ', url: 'https://example.com'),
        '4KVM\nhttps://example.com',
      );
    });

    test('trims the description', () {
      expect(
        shareTextFor(
          name: '4KVM',
          description: '  4K 高清影视。  \n',
          url: 'https://example.com',
        ),
        '4KVM\n4K 高清影视。\nhttps://example.com',
      );
    });
  });
}
