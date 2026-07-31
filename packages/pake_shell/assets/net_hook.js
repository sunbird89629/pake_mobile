(function () {
  if (window.__pakeNetHooked) return;
  window.__pakeNetHooked = true;

  var MAX_BODY = 8192;
  // 超过这个大小就完全不读 body。MAX_BODY 是「留多少」，这里是「读不读」——
  // 只有 MAX_BODY 的话，整个响应仍然会先被读成一个 JS 字符串再截断，页面在
  // 流式下发大响应时能直接把 WebView 撑爆。
  var MAX_CAPTURE = 1024 * 1024;

  function post(rec) {
    try {
      window.flutter_inappwebview.callHandler('pakeNet', rec);
    } catch (e) {
      // bridge 还没就绪就丢掉这条——不能因为记日志把页面搞崩。
    }
  }

  // 只有文本类响应值得抓。图片、音视频、字节流读出来是乱码，还得先整个进
  // 内存。event-stream 是无界的，也没有长度头，必须排除。
  function isTextual(type) {
    if (!type) return false;
    var t = String(type).toLowerCase();
    if (t.indexOf('text/event-stream') === 0) return false;
    return (
      t.indexOf('text/') === 0 ||
      t.indexOf('json') >= 0 ||
      t.indexOf('javascript') >= 0 ||
      t.indexOf('xml') >= 0 ||
      t.indexOf('x-www-form-urlencoded') >= 0
    );
  }

  function formatSize(bytes) {
    if (!(bytes >= 0)) return 'unknown size';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  // 跳过时留个说明，别让面板上出现一条既没 body 又没理由的记录。
  function skipMarker(bytes, type) {
    return (
      '(skipped: ' + formatSize(bytes) + ' ' + (type || 'unknown type') + ')'
    );
  }

  function contentLength(raw) {
    var n = parseInt(raw, 10);
    return isNaN(n) ? -1 : n;
  }

  function shouldSkipBody(length, type) {
    return !isTextual(type) || (length >= 0 && length > MAX_CAPTURE);
  }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var start = Date.now();
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var method = (init && init.method) || (input && input.method) || 'GET';

      return origFetch.apply(this, arguments).then(function (res) {
        var type = null;
        var length = -1;
        try {
          type = res.headers.get('content-type');
          length = contentLength(res.headers.get('content-length'));
        } catch (e) { /* 某些 polyfill 的 Response 没有 headers */ }

        // 先看头再决定读不读——读完再截断就已经晚了。
        if (shouldSkipBody(length, type)) {
          post({ url: url, method: method, status: res.status,
                 ms: Date.now() - start, body: skipMarker(length, type) });
          return res;
        }

        // 必须 clone——读掉原 response 的 body 会让页面自己读不到。
        res.clone().text().then(function (body) {
          post({ url: url, method: method, status: res.status,
                 ms: Date.now() - start, body: body.slice(0, MAX_BODY) });
        }).catch(function () {
          post({ url: url, method: method, status: res.status,
                 ms: Date.now() - start, body: '' });
        });
        return res;
      }).catch(function (err) {
        post({ url: url, method: method, status: -1,
               ms: Date.now() - start, body: String(err) });
        throw err;
      });
    };
  }

  var proto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
  if (proto) {
    var origOpen = proto.open;
    var origSend = proto.send;

    proto.open = function (method, url) {
      this.__pake = { method: method, url: url };
      return origOpen.apply(this, arguments);
    };

    proto.send = function () {
      var self = this;
      var start = Date.now();
      self.addEventListener('loadend', function () {
        var info = self.__pake || {};
        var type = null;
        var length = -1;
        try {
          type = self.getResponseHeader('content-type');
          length = contentLength(self.getResponseHeader('content-length'));
        } catch (e) { /* 某些状态下读不到响应头 */ }

        var body = '';
        if (self.responseType !== '' && self.responseType !== 'text') {
          // responseText 在这些 responseType 下会抛，内容本来也不是文本。
          body = skipMarker(length, type);
        } else if (shouldSkipBody(length, type)) {
          body = skipMarker(length, type);
        } else {
          try {
            body = String(self.responseText || '').slice(0, MAX_BODY);
          } catch (e) { /* 防御：规范外的实现仍可能抛 */ }
        }

        post({ url: info.url || '', method: info.method || 'GET',
               status: self.status, ms: Date.now() - start, body: body });
      });
      return origSend.apply(this, arguments);
    };
  }
})();
