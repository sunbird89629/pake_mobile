/* 4kvm 的 WebMCP 示例：把站点能力声明成 agent 可调用的工具。
   API 形态跟 WebMCP 草案（2026）：document.modelContext.registerTool({ name, description,
   inputSchema, execute, annotations })，execute 返回任意可 JSON 序列化的值。
   浏览器没有原生实现时退化成一个极简本地注册表，只在 window.__pakeWebmcp 上
   暴露 listTools / callTool，方便在 DevTools 里手动调；壳里还没有 agent，
   这份脚本目前只是示例，见 docs/roadmap.md「应用内 AI 助手」。 */
(() => {
  if (window.__pakeWebmcp) return; // 同一文档重复注入时别注册两遍

  const tools = new Map();
  const native = document.modelContext || navigator.modelContext; // 后者是旧草案的位置

  const register = (tool) => {
    tools.set(tool.name, tool);
    if (!native?.registerTool) return;
    // 原生实现遇到重名、schema 不合法会 reject；示例脚本不该因此把页面搞出未捕获错误。
    Promise.resolve(native.registerTool(tool)).catch((e) =>
      console.warn(`[pake-webmcp] registerTool ${tool.name} failed`, e),
    );
  };

  window.__pakeWebmcp = {
    native: Boolean(native?.registerTool),
    listTools: () =>
      [...tools.values()].map(({ name, description, inputSchema, annotations }) => ({
        name,
        description,
        inputSchema,
        annotations,
      })),
    callTool: async (name, input = {}) => {
      const tool = tools.get(name);
      if (!tool) throw new Error(`Unknown tool: ${name}`);
      for (const key of tool.inputSchema?.required ?? []) {
        if (input[key] == null) throw new Error(`Missing required input: ${key}`);
      }
      return tool.execute(input, { signal: new AbortController().signal });
    },
  };

  const text = (el) => el?.textContent.replace(/\s+/g, ' ').trim() ?? '';
  const abs = (href) => new URL(href, location.origin).href;

  const fetchDoc = async (path, signal) => {
    const res = await fetch(abs(path), { credentials: 'include', signal });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${path}`);
    return new DOMParser().parseFromString(await res.text(), 'text/html');
  };

  // 搜索结果、首页、分类页的海报卡片都是 `.group > a[href^="/play/"]`，
  // 里面 h3 是片名、左上角角标是年份。
  const parseCards = (doc) => {
    const seen = new Set();
    const items = [];
    for (const a of doc.querySelectorAll('a[href^="/play/"]')) {
      const url = abs(a.getAttribute('href'));
      const title = text(a.querySelector('h3')) || a.querySelector('img')?.alt || '';
      if (!title || a.classList.contains('episode-link') || seen.has(url)) continue;
      seen.add(url);
      const badge = [...a.querySelectorAll('div')].find((d) => /^\d{4}$/.test(text(d)));
      items.push({ title, year: badge ? text(badge) : null, url });
    }
    return items;
  };

  // 详情和播放是同一页（/play/<id>），「影片详情」抽屉里是 标签/值 两列的网格。
  const parseDetail = (doc, url) => {
    const drawer = [...doc.querySelectorAll('h2')].find((h) => text(h) === '影片详情')
      ?.closest('div')?.parentElement;
    const info = {};
    for (const label of drawer?.querySelectorAll('.col-span-1') ?? []) {
      info[text(label)] = text(label.nextElementSibling);
    }
    const synopsisEl = [...(drawer?.querySelectorAll('h3') ?? [])]
      .find((h) => text(h) === '剧情简介')?.nextElementSibling;
    // 简介里混着转义过的 WordPress 注释和 <p>，再解析一遍拿纯文本。
    const synopsis = text(new DOMParser().parseFromString(text(synopsisEl), 'text/html').body);
    const episodes = [...doc.querySelectorAll('a.episode-link[data-episode]')].map((a) => ({
      line: Number(a.dataset.line),
      episode: Number(a.dataset.episode),
      label: text(a),
      url: abs(a.getAttribute('href')),
    }));
    return {
      url,
      title: text(drawer?.querySelector('h1')) || text(doc.querySelector('h1')),
      info,
      synopsis,
      episodes,
    };
  };

  // untrustedContentHint：片名、简介来自站点数据库，agent 不该把它们当指令。
  const readOnly = { readOnlyHint: true, untrustedContentHint: true };

  if (location.hostname === 'www.4kvm.site' || location.hostname === '4kvm.site') {
    // 预设 URL 指向的是站方的地址发布页，这里只有一张镜像域名列表。
    register({
      name: 'list_mirror_domains',
      description: `List the 4kvm mirror domains published on this page, with the site's own
label for each (e.g. latest / primary / blocked in mainland China).`,
      inputSchema: { type: 'object', properties: {} },
      annotations: readOnly,
      execute: async () =>
        [...document.querySelectorAll('.content-top li')]
          .map((li) => ({ label: text(li.querySelector('b')), url: li.querySelector('a')?.href }))
          .filter((m) => m.label && m.url), // 末尾那条「请装 Chrome」提示没有 <b> 标签
    });
    return;
  }

  register({
    name: 'search_titles',
    description: `Search 4kvm for movies, TV series and anime by title (Chinese or English).
Returns up to 'limit' results with title, year and detail-page URL. Does not navigate.`,
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Title keywords, e.g. 流浪地球' },
        limit: { type: 'integer', minimum: 1, maximum: 50, default: 20 },
      },
      required: ['query'],
    },
    annotations: readOnly,
    execute: async ({ query, limit = 20 }, { signal }) => {
      const doc = await fetchDoc(`/search?q=${encodeURIComponent(query)}`, signal);
      return parseCards(doc).slice(0, limit);
    },
  });

  register({
    name: 'list_page_titles',
    description: `List the title cards visible on the current page (home, category, search
results or the related list on a detail page), with title, year and detail-page URL.`,
    inputSchema: { type: 'object', properties: {} },
    annotations: readOnly,
    execute: async () => ({ page: location.href, items: parseCards(document) }),
  });

  register({
    name: 'get_title_details',
    description: `Get details of a title: director, cast, genre, release date, runtime,
synopsis and the episode list. Defaults to the current page when 'url' is omitted.`,
    inputSchema: {
      type: 'object',
      properties: {
        url: { type: 'string', description: 'Detail-page URL from search_titles, /play/<id>' },
      },
    },
    annotations: readOnly,
    execute: async ({ url }, { signal }) => {
      if (!url) return parseDetail(document, location.href);
      return parseDetail(await fetchDoc(url, signal), abs(url));
    },
  });

  register({
    name: 'open_title',
    description: `Navigate the app to a title's detail/play page so the user can watch it.
Pass a URL returned by search_titles or get_title_details (an episode URL works too).`,
    inputSchema: {
      type: 'object',
      properties: { url: { type: 'string', description: 'Same-site /play/<id> URL' } },
      required: ['url'],
    },
    execute: async ({ url }) => {
      const target = new URL(url, location.origin);
      // 只放行本站播放页：别让一条被注入的站点文本把 agent 引去任意网址。
      if (target.origin !== location.origin || !target.pathname.startsWith('/play/')) {
        throw new Error(`Refusing to open non-4kvm URL: ${url}`);
      }
      location.assign(target.href);
      return { navigating: target.href };
    },
  });
})();
