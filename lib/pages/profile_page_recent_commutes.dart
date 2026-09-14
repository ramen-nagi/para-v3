import 'package:flutter/material.dart';
import 'package:para_v3/module/profile_list_page.dart';
import 'package:para_v3/module/profile_list_tile.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';
import 'package:para_v3/services/recents_service.dart';

class ProfilePageRecentCommutes extends StatefulWidget {
  final ValueChanged<Journey> onCommuteSelected;

  const ProfilePageRecentCommutes({
    super.key,
    required this.onCommuteSelected,
  });

  @override
  State<ProfilePageRecentCommutes> createState() =>
      _ProfilePageRecentCommutesState();
}

class _ProfilePageRecentCommutesState extends State<ProfilePageRecentCommutes> {
  List<RecentCommute> _commutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCommutes();
  }

  Future<void> _loadCommutes() async {
    try {
      final commutes = await RecentsService.instance.getRecentCommutes();
      if (!mounted) return;
      setState(() => _commutes = commutes);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteCommute(RecentCommute commute) async {
    await RecentsService.instance.deleteRecentCommute(commute.id);
    if (!mounted) return;
    setState(() => _commutes.removeWhere((item) => item.id == commute.id));
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent commutes?'),
        content: const Text(
          'This will remove all recent commutes from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await RecentsService.instance.clearRecentCommutes();
    if (!mounted) return;
    setState(_commutes.clear);
  }

  void _openCommute(Journey journey) {
    Navigator.of(context).pop();
    widget.onCommuteSelected(journey);
  }

  String _title(Journey journey) {
    final origin = journey.originMainText ?? journey.legs.first.fromStopName;
    final destination =
        journey.destinationMainText ?? journey.legs.last.toStopName;
    return '$origin → $destination';
  }

  String _subtitle(RecentCommute commute) {
    final journey = commute.journey;
    final modes = <VehicleType>[];
    for (final leg in journey.legs) {
      if (modes.isEmpty || modes.last != leg.vehicleType) {
        modes.add(leg.vehicleType);
      }
    }
    final modeText = modes.map(_vehicleLabel).join(' → ');
    return '${_formatStartedAt(commute.startedAt)} • $modeText';
  }

  String _vehicleLabel(VehicleType type) {
    switch (type) {
      case VehicleType.walk:
        return 'Walk';
      case VehicleType.train:
        return 'Train';
      case VehicleType.bus:
        return 'Bus';
      case VehicleType.jeep:
        return 'Jeep';
      case VehicleType.ejeep:
        return 'E-Jeep';
      case VehicleType.tricycle:
        return 'Tricycle';
      case VehicleType.uvExpress:
        return 'UV Express';
      case VehicleType.unknown:
        return 'Transit';
    }
  }

  String _formatStartedAt(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = dateTime.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return ProfileListPage(
      title: 'Recent Commutes',
      loading: _loading,
      isEmpty: _commutes.isEmpty,
      emptyMessage: 'No commute history yet',
      actions: _commutes.isEmpty
          ? null
          : [
              IconButton(
                tooltip: 'Clear recent commutes',
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
      children: [
        for (final commute in _commutes) ...[
          ProfileListTile(
            leading: const Icon(Icons.route_outlined),
            title: _title(commute.journey),
            subtitle: _subtitle(commute),
            trailing: IconButton(
              tooltip: 'Delete commute',
              onPressed: () => _deleteCommute(commute),
              icon: const Icon(Icons.delete_outline),
            ),
            onTap: () => _openCommute(commute.journey),
          ),
          const Divider(),
        ],
      ],
    );
  }
}
