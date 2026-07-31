/// URL 走明文 HTTP 时，两个平台都得显式放开传输安全策略，否则装上永远白屏。
///
/// 两个 patcher 共用一个定义：一边判 http 而另一边没判，就是「构建成功、
/// 运行必失败」，跟脚本 id 那次是同一类静默失效。
bool isCleartextUrl(String url) => Uri.tryParse(url)?.scheme == 'http';
