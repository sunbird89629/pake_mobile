import 'dart:io';

import 'package:debug_sheet/debug_sheet.dart';
import 'package:flutter/material.dart';
import 'package:pake_config/pake_config.dart';

import 'debug_ui.dart';
import 'lock/pattern_page.dart';
import 'log_page.dart';
import 'net/net_log.dart';
import 'net/net_log_page.dart';
import 'runtime_config.dart';
import 'update/update_check.dart';
import 'update/update_dialog.dart';
import 'update/update_service.dart';

const _customLabel = 'Custom…';

/// `DebugSelectSheet` 没有 `initialIndex`，`_selectedIndex` 恒从 0 起。
/// 把当前值排到首位即可预选，无需改上游包。
List<String> uaPresetOrder(String currentUa) {
  final names = [...UserAgentPresets.all.keys, _customLabel];
  final current =
      UserAgentPresets.all.entries
          .where((e) => e.value == currentUa)
          .map((e) => e.key)
          .firstOrNull ??
      _customLabel;

  return [current, ...names.where((n) => n != current)];
}

class DebugDrawer extends StatefulWidget {
  const DebugDrawer({
    super.key,
    required this.config,
    required this.onReloadRequested,
    required this.onClearCache,
    required this.netLog,
    this.logsDir,
    this.updateService,
    this.showDebugItems = kShowDebugSettings,
  });

  final RuntimeConfig config;
  final VoidCallback onReloadRequested;
  final Future<void> Function() onClearCache;

  /// WebView 抓的网络请求，来自 `WebViewPageState.netLog`——「View requests」
  /// 页面直接读它。
  final NetLog netLog;

  /// `logger_utils` 的日志落盘目录，由 `main.dart` 用 `path_provider` 算出来
  /// 再一路传下来。测试里不传——用不到「View logs」的场景不需要它。
  final String? logsDir;

  /// 只为测试注入。生产路径上现造一个——它没有状态，`UpdateService` 的
  /// 全部状态都在 `RuntimeConfig` 里。
  final UpdateService? updateService;

  /// 显不显示调试项，默认跟着构建模式走（[kShowDebugSettings]）。
  ///
  /// 之所以还留一个参数：widget 测试永远跑在 debug 模式下，那个 const 在
  /// 测试里恒为 true，不显式传 false 就没法覆盖正式包那条路径。
  final bool showDebugItems;

  @override
  State<DebugDrawer> createState() => _DebugDrawerState();
}

class _DebugDrawerState extends State<DebugDrawer> {
  RuntimeConfig get _config => widget.config;

  /// `DebugInputSheet` 内部用了 Expanded + ListView，
  /// 必须给有界高度，否则布局崩。
  Future<T?> _showSheet<T>(Widget child) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: child,
    ),
  );

  Future<void> _editUrl() async {
    final entered = await _showSheet<String>(
      const DebugInputSheet(title: 'Load URL'),
    );
    // 下滑取消时返回 null——不能直接 `!`。
    if (entered == null || entered.isEmpty) return;

    _config.url = entered;
    setState(() {});
    widget.onReloadRequested();
  }

  Future<void> _editUserAgent() async {
    final order = uaPresetOrder(_config.userAgent);
    final index = await _showSheet<int>(
      DebugSelectSheet(title: 'User agent', items: order),
    );
    if (index == null) return;

    final choice = order[index];
    if (choice == _customLabel) {
      final custom = await _showSheet<String>(
        const DebugInputSheet(title: 'Custom user agent'),
      );
      if (custom == null || custom.isEmpty) return;
      _config.userAgent = custom;
    } else {
      _config.userAgent = UserAgentPresets.all[choice]!;
    }

    setState(() {});
    widget.onReloadRequested();
  }

  void _toggleScript(String id, bool enabled) {
    _config.setScriptEnabled(id, enabled);
    setState(() {});
    // addUserScript/removeUserScript 只在下一次加载生效，所以必须 reload。
    widget.onReloadRequested();
  }

  /// 取消对话框就什么都不写——开关下一次 build 读回 false，自己弹回去。
  Future<void> _enableAppLock() async {
    final hash = await showPatternPage(context);
    if (hash == null) return;

    _config
      ..patternHash = hash
      ..appLockEnabled = true;
    setState(() {});
  }

  /// 不二次验证：人能站在设置页里，说明刚才已经画对过图案了。
  void _disableAppLock() {
    _config
      ..appLockEnabled = false
      ..patternHash = null;
    setState(() {});
  }

  Future<void> _changePattern() async {
    final hash = await showPatternPage(context);
    if (hash == null) return;

    _config.patternHash = hash;
    setState(() {});
  }

  bool _checking = false;

  /// 手动检查：无视开关与节流，并且**回显结果**——包括「已是最新版」和错误。
  /// 自动路径必须静默（墙内查不到是常态），但用户主动点了按钮却什么都不显示
  /// 是另一回事。
  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);

    String message;
    UpdateInfo? info;
    try {
      info = await (widget.updateService ?? UpdateService(_config)).check();
      message = info == null
          ? 'Already on the latest version (${_config.buildTime.version})'
          : 'Version ${info.version} is available';
    } catch (e) {
      message = 'Check failed: $e';
    }

    if (!mounted) return;
    setState(() => _checking = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: info == null
            ? null
            : SnackBarAction(
                label: 'Download',
                onPressed: () => openDownload(info!.downloadUrl),
              ),
      ),
    );
  }

  void _reset() {
    _config.reset();
    setState(() {});
    widget.onReloadRequested();
  }

  @override
  Widget build(BuildContext context) {
    // 开关的键必须是 id，不能是 pake.json 里的原始路径——运行期的启用集合
    // 和 index.json 用的都是 id。id 本身（`hide-ads`）也正好是可读的标题。
    final scripts = _config.buildTime.injectScripts.map(scriptIdFor).toList();
    final enabled = _config.enabledScripts;
    final debug = widget.showDebugItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (debug) ...[
            ListTile(
              title: const Text('URL'),
              subtitle: Text(_config.url),
              trailing: const Icon(Icons.edit),
              onTap: _editUrl,
            ),
            ListTile(
              title: const Text('User agent'),
              subtitle: Text(
                _config.userAgent.isEmpty
                    ? 'System default'
                    : _config.userAgent,
              ),
              trailing: const Icon(Icons.edit),
              onTap: _editUserAgent,
            ),
            const Divider(),
          ],
          // 一个脚本都没打包进来时整组不出现——只剩标题和「toggling a script
          // reloads the page」的说明、底下一个开关都没有，是在讲一件这个 app
          // 里不存在的事。正式包里它还正好落在页面顶部。
          if (scripts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Inject scripts'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Toggling a script reloads the page — scripts only take '
                'effect on the next page load.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            for (final id in scripts)
              SwitchListTile(
                key: ValueKey('script:$id'),
                title: Text(id),
                value: enabled.contains(id),
                onChanged: (on) => _toggleScript(id, on),
              ),
            const Divider(),
          ],
          if (debug) ...[
            SwitchListTile(
              title: const Text('Capture network'),
              subtitle: const Text(
                'Hooks the page\'s fetch and XHR to fill the requests list.',
              ),
              value: _config.captureNetwork,
              onChanged: (on) {
                _config.captureNetwork = on;
                setState(() {});
                widget.onReloadRequested();
              },
            ),
            const Divider(),
          ],
          SwitchListTile(
            key: const ValueKey('appLock'),
            title: const Text('App lock'),
            subtitle: const Text(
              'Asks for a pattern on launch and after 30 seconds in the '
              'background. Forgetting it means clearing app data — there is '
              'no recovery.',
            ),
            value: _config.appLockEnabled,
            onChanged: (on) => on ? _enableAppLock() : _disableAppLock(),
          ),
          if (_config.appLockEnabled)
            ListTile(
              key: const ValueKey('changePattern'),
              title: const Text('Change pattern'),
              leading: const Icon(Icons.pattern),
              onTap: _changePattern,
            ),
          const Divider(),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(_config.buildTime.version),
            leading: const Icon(Icons.info_outline),
          ),
          ListTile(
            key: const ValueKey('checkForUpdates'),
            title: const Text('Check for updates'),
            leading: const Icon(Icons.system_update),
            trailing: _checking
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _checking ? null : _checkForUpdates,
          ),
          // iOS 上不显示：侧载的 IPA 装不上，自动提示只是在报告一件用户
          // 无能为力的事。手动那一行两端都留着。
          if (!Platform.isIOS)
            SwitchListTile(
              key: const ValueKey('updateCheckEnabled'),
              title: const Text('Check on launch'),
              subtitle: const Text(
                'Asks GitHub for a newer build at most once a day.',
              ),
              value: _config.updateCheckEnabled,
              onChanged: (on) {
                _config.updateCheckEnabled = on;
                setState(() {});
              },
            ),
          const Divider(),
          ListTile(
            title: const Text('Clear cache & cookies'),
            leading: const Icon(Icons.delete_sweep),
            onTap: () async {
              await widget.onClearCache();
              widget.onReloadRequested();
            },
          ),
          if (debug) ...[
            ListTile(
              title: const Text('View logs'),
              leading: const Icon(Icons.article),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogPage(logsDir: widget.logsDir),
                ),
              ),
            ),
            ListTile(
              title: const Text('View requests'),
              leading: const Icon(Icons.swap_vert),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NetLogPage(log: widget.netLog),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Reset to build defaults'),
              leading: const Icon(Icons.restart_alt),
              onTap: _reset,
            ),
          ],
        ],
      ),
    );
  }
}
