# pake_mobile

把任意网页打包成 Android / iOS App。一套 Dart 代码出双端。

## 用法

```bash
dart pub global activate --source path packages/pake_cli

pakem init                                    # 生成 pake.json 模板
pakem build https://m.weibo.cn --name Weibo --bundle-id com.pake.weibo
pakem build https://m.weibo.cn --platform android,ios --team-id ABCDE12345 --profile "Pake Dev"
pakem icon https://m.weibo.cn/favicon.ico
pakem doctor
```

产物在 `~/.pake/workspace/build/`，构建日志在 `~/.pake/logs/`。

## 配置分两层

| | 构建期 `pake.json` | 运行期（设置页） |
|---|---|---|
| 内容 | app 名、bundle id、图标、版本号、初始 URL、系统权限 | 当前 URL、UA、注入脚本开关、缓存策略 |
| 谁写 | CLI | 设置页 |

改 UA 不需要重新构建。运行期层为空时回落构建期默认；「重置」= 清空运行期层。

## 设置页入口

网页左上角**长按 1.5 秒**。这个入口在网页白屏时同样可用——这是刻意设计，
否则一个错误的 URL 会让 app 变砖。

## 退出码

`1` 配置错误 · `2` 环境缺失 · `3` 构建失败。`--json` 模式下错误同样是 JSON。

## 开发

```bash
cd packages/pake_config && dart test
cd packages/pake_cli && dart test          # smoke test 默认跳过
cd packages/pake_shell && flutter test
```

跑一次真实构建（数分钟，冷 Gradle）：

```bash
cd packages/pake_cli && dart test --tags smoke --run-skipped
```

`--tags smoke` 只选中用例，不解除 `dart_test.yaml` 里的 `skip:`；
必须带 `--run-skipped` 才会真正执行，CI 的 build workflow 用的是
同一条命令。

发版前跑 [手动回归清单](docs/manual-regression.md)。
