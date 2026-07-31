import 'package:debug_sheet/debug_sheet.dart';
import 'package:flutter/material.dart';
import 'package:pake_config/pake_config.dart';

import 'log_page.dart';
import 'runtime_config.dart';

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
    this.logsDir,
  });

  final RuntimeConfig config;
  final VoidCallback onReloadRequested;
  final Future<void> Function() onClearCache;

  /// `logger_utils` 的日志落盘目录，由 `main.dart` 用 `path_provider` 算出来
  /// 再一路传下来。测试里不传——用不到「View logs」的场景不需要它。
  final String? logsDir;

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

  void _reset() {
    _config.reset();
    setState(() {});
    widget.onReloadRequested();
  }

  @override
  Widget build(BuildContext context) {
    final scripts = _config.buildTime.injectScripts;
    final enabled = _config.enabledScripts;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('URL'),
            subtitle: Text(_config.url),
            trailing: const Icon(Icons.edit),
            onTap: _editUrl,
          ),
          ListTile(
            title: const Text('User agent'),
            subtitle: Text(
              _config.userAgent.isEmpty ? 'System default' : _config.userAgent,
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editUserAgent,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Inject scripts'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Toggling a script reloads the page — scripts only take effect '
              'on the next page load.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final id in scripts)
            SwitchListTile(
              title: Text(id),
              value: enabled.contains(id),
              onChanged: (on) => _toggleScript(id, on),
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
          ListTile(
            title: const Text('View logs'),
            leading: const Icon(Icons.article),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LogPage(logsDir: widget.logsDir),
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
      ),
    );
  }
}
