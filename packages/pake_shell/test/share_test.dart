import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/share.dart';

void main() {
  group('shareTextFor', () {
    test('puts the title on its own line above the url', () {
      expect(
        shareTextFor(url: 'https://4kvm.site/v/1', title: '沙丘 2'),
        '沙丘 2\nhttps://4kvm.site/v/1',
      );
    });

    test('sends the bare url when there is no title', () {
      // WebView 的 getTitle() 在页面还没解析出 <title> 时返回 null。
      expect(shareTextFor(url: 'https://example.com'), 'https://example.com');
      expect(
        shareTextFor(url: 'https://example.com', title: ''),
        'https://example.com',
      );
      expect(
        shareTextFor(url: 'https://example.com', title: '   '),
        'https://example.com',
      );
    });

    test('does not repeat a title that is just the url', () {
      // 站点不给 <title> 时 WebView 会把地址本身当标题返回，直接拼就成了
      // 同一条链接连发两遍。
      expect(
        shareTextFor(url: 'https://example.com', title: 'https://example.com'),
        'https://example.com',
      );
    });

    test('trims the title', () {
      expect(
        shareTextFor(url: 'https://example.com', title: '  Home \n'),
        'Home\nhttps://example.com',
      );
    });
  });
}
