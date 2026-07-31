(function () {
  if (window.__pakeNetHooked) return;
  window.__pakeNetHooked = true;

  var MAX_BODY = 8192;

  function post(rec) {
    try {
      window.flutter_inappwebview.callHandler('pakeNet', rec);
    } catch (e) {
      // bridge 还没就绪就丢掉这条——不能因为记日志把页面搞崩。
    }
  }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var start = Date.now();
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var method = (init && init.method) || (input && input.method) || 'GET';

      return origFetch.apply(this, arguments).then(function (res) {
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
        var body = '';
        try {
          if (self.responseType === '' || self.responseType === 'text') {
            body = String(self.responseText || '').slice(0, MAX_BODY);
          }
        } catch (e) { /* responseText 在某些 responseType 下会抛 */ }

        post({ url: info.url || '', method: info.method || 'GET',
               status: self.status, ms: Date.now() - start, body: body });
      });
      return origSend.apply(this, arguments);
    };
  }
})();
