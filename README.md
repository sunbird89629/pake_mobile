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

产物归档在 `~/.pake/out/<app>/`，构建日志在 `~/.pake/logs/`。

workspace 是跨 app 复用的单一 Flutter 项目，`~/.pake/workspace/build/` 里那份
会被下一次构建原地覆盖——`pakem build` 报出来的、也是该拿去装的，是
`~/.pake/out/<app>/` 里的归档副本。

## 配置分两层

| | 构建期 `pake.json` | 运行期（设置页） |
|---|---|---|
| 内容 | app 名、bundle id、图标、版本号、初始 URL、系统权限 | 当前 URL、UA、注入脚本开关、缓存策略 |
| 谁写 | CLI | 设置页 |

改 UA 不需要重新构建。运行期层为空时回落构建期默认；「重置」= 清空运行期层。

## 设置页入口

网页左上角**长按 1.5 秒**。这个入口在网页白屏时同样可用——这是刻意设计，
否则一个错误的 URL 会让 app 变砖。

## 应用锁

设置页里可以开一道四位 PIN 锁：冷启动时锁，切后台超过 30 秒回来也锁。
PIN 明文存在运行期配置里，防的是别人拿起你的手机，不是取证分析。

**忘了 PIN 没有恢复路径**——锁屏盖住了长按左上角那个入口，只能清应用数据
或重装。这是刻意的：留后门的锁不叫锁。

## 退出码

`1` 配置错误 · `2` 环境缺失 · `3` 构建失败。`--json` 模式下错误同样是 JSON。

## Android 发布签名

不配密钥也能出包，但会用 Flutter 的 debug key 签——**那种 APK 换台机器
或换一次 CI 运行，签名指纹就变了**，装不到已有安装之上，也无法升级。
`pakem build` 的结果里 `androidSigning` 字段写明本次到底用了哪种。

配置方式是在 `~/.pake/signing.properties` 放四行（`storeFile` 用绝对路径）：

```properties
storeFile=/Users/you/.pake/pake-release.p12
storePassword=…
keyAlias=pake
keyPassword=…
```

没有密钥就先生成一个：

```bash
keytool -genkeypair -v -keystore ~/.pake/pake-release.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias pake \
  -dname "CN=pake, O=pake_mobile, C=CN"
chmod 600 ~/.pake/pake-release.p12 ~/.pake/signing.properties
```

这个文件放在 workspace 之外是必须的：`~/.pake/workspace` 每次构建都会被
模板覆写，放里面会被冲掉；放仓库里则等于把私钥提交上去。

**keystore 丢了就没法再给同一个 app 发更新**，用户只能卸载重装。备份它。

CI 用同一套约定，密钥来自三个 repo secret：`ANDROID_KEYSTORE_BASE64`
（`base64 < keystore.p12 | tr -d '\n'`）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`。没设这些 secret 时 build workflow 照常出包，但会在
job summary 里标出 debug 签名并给一条 warning。

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
