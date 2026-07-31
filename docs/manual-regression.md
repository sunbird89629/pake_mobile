# 手动回归清单

需真机 + 真站点，自动化无法覆盖。每次发版执行。
以下四项来自 PakePlus-Android 的实际踩坑记录。

- [ ] **WASM streaming compile** —— 加载依赖 `WebAssembly.instantiateStreaming` 的站点。
      已有 shim 修复经验，若复发按同样思路在注入脚本里补 shim。
- [ ] **`blob:` / `data:` URL 下载** —— 触发一次页面内导出/下载，确认文件真的落盘。
- [ ] **输入法遮挡** —— 点页面底部输入框，确认键盘不遮挡（`windowSoftInputMode=adjustResize`）。
- [ ] **4K 视频播放** —— Pixel 8 已验证基线，确认不卡顿、不黑屏。

外加壳自身的四项：

- [ ] 左上角长按 1.5 秒能打开设置（在**网页白屏时**也要试一次）。
- [ ] 改 URL → 页面跳转；重启 app 后仍是新 URL。
- [ ] 切 UA → 页面 reload，站点识别为对应设备。
- [ ] 「重置」后回落到构建时的 URL 与 UA。
