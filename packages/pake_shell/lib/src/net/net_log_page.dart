import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'net_log.dart';
import 'net_record.dart';

class NetLogPage extends StatefulWidget {
  const NetLogPage({super.key, required this.log});

  final NetLog log;

  @override
  State<NetLogPage> createState() => _NetLogPageState();
}

class _NetLogPageState extends State<NetLogPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(widget.log.clear),
          ),
        ],
      ),
      body: StreamBuilder<void>(
        stream: widget.log.changes,
        builder: (context, _) {
          final records = widget.log.records;
          if (records.isEmpty) {
            return const Center(child: Text('No requests captured yet.'));
          }
          return ListView.separated(
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemCount: records.length,
            itemBuilder: (context, i) => _tile(records[i]),
          );
        },
      ),
    );
  }

  Widget _tile(NetRecord r) => ListTile(
    dense: true,
    leading: Text(
      r.status <= 0 ? '—' : '${r.status}',
      style: TextStyle(
        color: r.status >= 400 || r.status < 0
            ? Colors.red
            : Colors.green.shade700,
      ),
    ),
    title: Text(r.url, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${r.method} · ${r.durationMs}ms · ${r.source.name}'),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _DetailPage(record: r))),
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.record});

  final NetRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy as cURL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: record.toCurl()));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied as cURL')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText('${record.method} ${record.url}'),
          const SizedBox(height: 8),
          Text('Status ${record.status} · ${record.durationMs}ms'),
          if (record.source == NetSource.resource)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Captured via onLoadResource — body is not available for '
                'resource loads.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const Divider(height: 32),
          SelectableText(
            record.body ?? '(no body)',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
