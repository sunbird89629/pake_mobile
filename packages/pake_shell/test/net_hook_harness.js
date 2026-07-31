// net_hook.js 的测试宿主：搭一个最小的 window / fetch / XMLHttpRequest，
// 加载真实的 assets/net_hook.js，跑一组场景，把抓到的记录打成 JSON。
//
// 关键点是 `bodyReads`：它统计 body 到底被读进内存过几次。断言「body 是那条
// skip 说明」还不够——真正要防的是「先整个读进来、再截断成一句说明」，
// 那样的实现照样能通过内容断言，却依然会把 WebView 撑爆。
const fs = require('fs');
const vm = require('vm');

const hookSource = fs.readFileSync(process.argv[2], 'utf8');

const posted = [];
let bodyReads = 0;

function makeResponse({ status = 200, type, length, body = 'x' }) {
  const headers = {
    get(name) {
      const n = String(name).toLowerCase();
      if (n === 'content-type') return type ?? null;
      if (n === 'content-length') return length == null ? null : String(length);
      return null;
    },
  };
  const res = {
    status,
    headers,
    clone() {
      return {
        text() {
          bodyReads++;
          return Promise.resolve(body);
        },
      };
    },
  };
  return res;
}

class FakeXHR {
  constructor(headers, responseText, responseType = '') {
    this._headers = headers;
    this._responseText = responseText;
    this.responseType = responseType;
    this.status = 200;
    this._listeners = {};
  }
  get responseText() {
    bodyReads++;
    return this._responseText;
  }
  getResponseHeader(name) {
    return this._headers[String(name).toLowerCase()] ?? null;
  }
  addEventListener(event, fn) {
    (this._listeners[event] ||= []).push(fn);
  }
  fire(event) {
    for (const fn of this._listeners[event] || []) fn();
  }
  open() {}
  send() {}
}

const window = {
  fetch: (input, init) => Promise.resolve(window.__nextResponse),
  XMLHttpRequest: FakeXHR,
  flutter_inappwebview: {
    callHandler(name, rec) {
      posted.push(rec);
    },
  },
};
window.window = window;

vm.createContext(window);
vm.runInContext(hookSource, window);

async function fetchCase(name, responseInit) {
  window.__nextResponse = makeResponse(responseInit);
  const before = bodyReads;
  await window.fetch('https://example.com/' + name);
  // fetch 的 body 是异步读的，等一拍微任务。
  await new Promise((r) => setTimeout(r, 0));
  return { name, record: posted.pop(), bodyReads: bodyReads - before };
}

function xhrCase(name, headers, text, responseType) {
  const xhr = new window.XMLHttpRequest(headers, text, responseType);
  xhr.open('GET', 'https://example.com/' + name);
  xhr.send();
  const before = bodyReads;
  xhr.fire('loadend');
  return { name, record: posted.pop(), bodyReads: bodyReads - before };
}

(async () => {
  const results = [];

  results.push(
    await fetchCase('small-json', {
      type: 'application/json',
      length: 20,
      body: '{"ok":true}',
    }),
  );
  results.push(
    await fetchCase('huge-json', {
      type: 'application/json',
      length: 50 * 1024 * 1024,
      body: 'never read',
    }),
  );
  results.push(
    await fetchCase('image', {
      type: 'image/jpeg',
      length: 13 * 1024 * 1024,
      body: 'never read',
    }),
  );
  results.push(
    await fetchCase('event-stream', {
      type: 'text/event-stream',
      body: 'never read',
    }),
  );
  results.push(
    await fetchCase('html-no-length', {
      type: 'text/html; charset=utf-8',
      body: '<html></html>',
    }),
  );
  results.push(
    await fetchCase('long-text', {
      type: 'text/plain',
      length: 900000,
      body: 'a'.repeat(20000),
    }),
  );

  results.push(
    xhrCase(
      'xhr-json',
      { 'content-type': 'application/json', 'content-length': '11' },
      '{"ok":true}',
    ),
  );
  results.push(
    xhrCase(
      'xhr-huge',
      {
        'content-type': 'application/json',
        'content-length': String(50 * 1024 * 1024),
      },
      'never read',
    ),
  );
  results.push(
    xhrCase(
      'xhr-image',
      { 'content-type': 'image/png', 'content-length': '2048' },
      'never read',
    ),
  );
  results.push(
    xhrCase(
      'xhr-arraybuffer',
      { 'content-type': 'application/octet-stream' },
      'never read',
      'arraybuffer',
    ),
  );

  process.stdout.write(JSON.stringify(results));
})();
