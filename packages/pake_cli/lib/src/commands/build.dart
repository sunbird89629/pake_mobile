import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:pake_config/pake_config.dart';
import 'package:path/path.dart' as p;

import '../build_pipeline.dart';
import '../icon_discovery.dart';
import '../materialize.dart';
import '../output.dart';
import '../patch/ios.dart';
import '../process_runner.dart';
import '../signing.dart';
import '../workspace.dart';
import 'icon.dart' show decodedIconSize, fetchIconBytes;

/// 最多下载几个图标候选。
///
/// 候选队列末尾是 Google favicon 那种保底项，一路试到底意义不大，而每次
/// 尝试都是一趟真实网络请求——墙内每趟都要等超时。三次足够跨过「SVG 解不了」
/// 和「后缀骗人」这两种常见情况。
const _maxIconAttempts = 3;

/// 到这个尺寸就不再往下找了。
///
/// 192 是 `androidIconSizes` 里最大的那档（xxxhdpi），拿到它就不需要放大。
/// 没有这道门槛的话「第一个能解码的」会赢——x.com 那条队列里它是 32×32 的
/// favicon.ico，而再往后一个是 512×512。
const _goodEnoughIconSize = 192;

class BuildCommand extends Command<int> {
  BuildCommand(
    this._output, {
    ProcessRunner? runner,
    Workspace? workspace,
    String? templateDir,
  }) : _runner = runner ?? const RealProcessRunner(),
       _workspace = workspace ?? Workspace(),
       _templateDirOverride = templateDir {
    argParser
      // 默认 android：iOS 需要签名参数，静默尝试双端后失败会让首次
      // 使用者困惑。要 iOS 就显式写出来。
      ..addOption('platform', defaultsTo: 'android')
      ..addOption('config')
      ..addOption('name')
      ..addOption('icon')
      ..addOption('bundle-id')
      ..addOption('version')
      ..addOption('team-id')
      ..addOption('profile')
      ..addMultiOption('inject');
  }

  final Output _output;
  final ProcessRunner _runner;
  final Workspace _workspace;
  final String? _templateDirOverride;

  @override
  String get name => 'build';

  @override
  String get description => 'Build the given URL into an app.';

  @override
  String get invocation => 'pakem build <url> [options]';

  /// `pake_shell` 模板包的路径。
  ///
  /// 不用 `Platform.script`——在 `dart test` 下它指向一个临时 `.dill`
  /// 文件，不是源码位置。`package:pake_cli/` 经 package_config.json
  /// 解析到 `pake_cli/lib/`，在 isolate 启动时就固定好，测试和真正
  /// 安装的 CLI（`dart pub global activate --source path`）下都成立。
  /// `pake_shell` 是 Flutter 包、不是 pake_cli 的依赖，没法直接用
  /// `package:pake_shell/` 解析，只能从 `pake_cli/lib/` 相对上溯。
  Future<String> _resolveTemplateDir() async {
    final override = _templateDirOverride;
    if (override != null) return override;

    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:pake_cli/'),
    );
    return p.normalize(p.join(libUri!.toFilePath(), '..', '..', 'pake_shell'));
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final url = args.rest.isEmpty ? null : args.rest.first;

    final config = mergeConfig(
      fileJson: loadConfigJson(
        explicitPath: args.option('config'),
        cwd: Directory.current.path,
      ),
      flags: PakeFlags(
        name: args.option('name'),
        url: url,
        bundleId: args.option('bundle-id'),
        version: args.option('version'),
        iconPath: args.option('icon'),
        injectScripts: args.wasParsed('inject')
            ? args.multiOption('inject')
            : null,
      ),
    );

    final errors = validateConfig(config);
    if (errors.isNotEmpty) {
      throw PakeException(
        ExitCodes.config,
        'Invalid configuration (${errors.length} problem(s)).',
        details: errors,
      );
    }

    // 图标优先级链：A (--icon 显式指定) → B-E (自动发现)。
    // --icon 给了就直接用；没给则从网站 HTML / manifest / favicon.ico
    // 按优先级找，下载到临时文件再交给 materializeConfig。
    var resolvedConfig = config;
    // 图标最终从哪来，要能在结果里读到。回落是静默的（`info` 在 `--json`
    // 下不输出），在线构建的人只会看到包里是默认图标，无从判断是站点没图标、
    // 下载失败、还是抓到的根本不是图片。
    var iconSource = config.iconPath ?? 'default';
    if (config.iconPath == null) {
      // 评分排第一的未必能用：后缀会骗人（`x.com/apple-touch-icon.png` 返回
      // 287KB 的首页 HTML），格式也未必解得了。逐个试到解得开为止——只赌
      // 第一个的话，站点明明还有能用的图标也拿不到。
      final candidates = await discoverIconUrls(config.url);

      List<int>? bestBytes;
      var bestSize = 0;

      for (final candidate in candidates.take(_maxIconAttempts)) {
        _output.info('Icon: $candidate');
        try {
          final bytes = await fetchIconBytes(candidate);
          // 下载成功 ≠ 拿到了图片。不在这里挡住的话，解码要到
          // materializeConfig 里才炸，而那已经在这个 try 之外——自动发现
          // 猜错一次，代价是整个构建失败。
          final size = decodedIconSize(bytes);
          if (size == null) {
            _output.info('  not a usable image, trying the next candidate.');
            continue;
          }

          if (size > bestSize) {
            bestBytes = bytes;
            bestSize = size;
            // 记发现它的 URL，不是那个临时文件路径——`.icon-auto.png` 对
            // 读结果的人没有任何意义。
            iconSource = candidate;
          }

          // 够大就不必再下了。不够大也不能立刻收工：x.com 的第二候选是
          // 32×32 的 favicon.ico，而第三个才是 512×512 那张。
          if (bestSize >= _goodEnoughIconSize) break;
          _output.info('  only ${size}px, looking for something larger.');
        } catch (e) {
          _output.info('  download failed ($e), trying the next candidate.');
        }
      }

      if (bestBytes == null) {
        _output.info('No usable icon found, using the default one.');
      } else {
        final tmp = File(p.join(_workspace.root, '.icon-auto.png'));
        tmp.writeAsBytesSync(bestBytes);
        resolvedConfig = config.copyWith(iconPath: tmp.path);
      }
    }

    final platforms = args
        .option('platform')!
        .split(',')
        .map((s) => PakePlatform.byName(s.trim()))
        .toList();

    String? exportOptionsPath;
    if (platforms.contains(PakePlatform.ios)) {
      final teamId = args.option('team-id');
      final profileName = args.option('profile');
      if (teamId == null || profileName == null) {
        throw PakeException(
          ExitCodes.config,
          'iOS builds need --team-id and --profile.',
        );
      }

      await checkIosSigning(
        runner: _runner,
        profileName: profileName,
        bundleId: config.bundleId,
        profiles: await loadInstalledProfiles(_runner),
      );

      exportOptionsPath = p.join(_workspace.root, 'ExportOptions.plist');
      File(exportOptionsPath).writeAsStringSync(
        exportOptionsPlist(
          teamId: teamId,
          profileName: profileName,
          bundleId: config.bundleId,
        ),
      );
    }

    final templateDir = await _resolveTemplateDir();

    final artifacts = await _workspace.withLock(() async {
      syncTemplate(templateDir: templateDir, projectDir: _workspace.projectDir);
      materializeConfig(
        config: resolvedConfig,
        workspace: _workspace,
        cwd: Directory.current.path,
        templateDir: templateDir,
      );

      return runBuild(
        config: config,
        platforms: platforms,
        workspace: _workspace,
        runner: _runner,
        output: _output,
        exportOptionsPath: exportOptionsPath,
      );
    });

    // 归档后才报路径：workspace 里的那份下次构建就被覆盖了，交给用户的
    // 必须是 `~/.pake/out/<app>/` 里那份留得住的。
    final archived = archiveArtifacts(
      artifacts: artifacts,
      workspace: _workspace,
      appName: config.name,
    );

    _output.success({
      'app': config.name,
      // 版本没填时回落 CLI 默认值，机器读结果时不该还要自己猜是哪一版——
      // 在线构建的 release notes 正是靠这个字段显示版本的。
      'version': config.version,
      // 实际用上的图标来源，或 `default`（自动发现没成，用了模板自带那张）。
      'icon': iconSource,
      'artifacts': archived,
      'archivedInto': _workspace.outDirFor(config.name),
      // 让「这个包到底是不是正式签名」在结果里直接可读，而不是等装机时
      // 撞上 INSTALL_FAILED_UPDATE_INCOMPATIBLE 才发现。
      if (platforms.contains(PakePlatform.android))
        'androidSigning': androidSigningMode(),
    });
    return 0;
  }
}
