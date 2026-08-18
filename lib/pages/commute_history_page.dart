import 'package:flutter/material.dart';
import 'package:para_v3/services/commute_history_service.dart';

class CommuteHistoryPage extends StatefulWidget {
  const CommuteHistoryPage({super.key});

  @override
  State<CommuteHistoryPage> createState() => _CommuteHistoryPageState();
}

class _CommuteHistoryPageState extends State<CommuteHistoryPage> {
  List<CommuteHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await CommuteHistoryService.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear commute history?'),
        content: const Text(
          'This removes completed commutes from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CommuteHistoryService.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Commute history'),
      actions: [
        if (_entries.isNotEmpty)
          IconButton(
            tooltip: 'Clear history',
            onPressed: _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _entries.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No completed commutes yet.\nFinish a journey to see it here.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final local = entry.completedAt.toLocal();
              final date =
                  '${local.day}/${local.month}/${local.year} at '
                  '${local.hour.toString().padLeft(2, '0')}:'
                  '${local.minute.toString().padLeft(2, '0')}';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text('${entry.origin} → ${entry.destination}'),
                  subtitle: Text(date),
                ),
              );
            },
          ),
  );
}
