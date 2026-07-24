import 'package:flutter/material.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  final TextEditingController _searchController = TextEditingController();
  RouteModel? _selectedRoute;

  @override
  void initState() {
    super.initState();
    // Listen for database download completion updates
    GtfsNetworkService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    GtfsNetworkService.instance.removeListener(_onServiceUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    setState(() {}); // Rebuild UI when database finishes downloading/loading
  }

  void _performSearchAndPrint() {
    FocusScope.of(context).unfocus();
    final query = _searchController.text.trim();

    final matches = GtfsNetworkService.instance.searchRoutesByLongName(query);

    if (matches.isEmpty) {
      setState(() => _selectedRoute = null);
      debugPrint('--- [SEARCH RESULT] No routes found matching: "$query" ---');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No routes found matching "$query"')),
      );
      return;
    }

    final route = matches.first;
    setState(() => _selectedRoute = route);

    // --- PRINT DETAILED DEBUG INFO TO TERMINAL ---
    debugPrint('==================================================');
    debugPrint('ROUTE FOUND: ${route.routeLongName}');
    debugPrint('ROUTE ID:    ${route.routeId}');
    debugPrint('TOTAL TRIPS: ${route.trips.length}');
    debugPrint('--------------------------------------------------');

    for (int i = 0; i < route.trips.length; i++) {
      final trip = route.trips[i];
      debugPrint(
        ' TRIP [${i + 1}]: ${trip.tripId} (Shape ID: ${trip.shapeId ?? "N/A"})',
      );
      debugPrint('   STOPS (${trip.stopTimes.length} total):');
      for (final st in trip.stopTimes) {
        debugPrint(
          '     - [Seq ${st.stopSequence}] ${st.stopName} (${st.stopId})',
        );
      }
    }
    debugPrint('==================================================');
  }

  @override
  Widget build(BuildContext context) {
    final service = GtfsNetworkService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Routes Search')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Sync status banner
            if (service.isDownloading)
              const LinearProgressIndicator()
            else if (!service.isLoaded)
              const Text(
                'Syncing GTFS Database...',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              const Text(
                '✓ GTFS Database Loaded & Ready',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 16),

            // Search Bar & Button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Enter route long name (e.g., Philcoa)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: service.isLoaded ? _performSearchAndPrint : null,
                  child: const Text('Verify'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Route Details Verification Display
            Expanded(
              child: _selectedRoute == null
                  ? const Center(
                      child: Text(
                        'Enter a route name and tap Verify to inspect data.',
                      ),
                    )
                  : ListView(
                      children: [
                        Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedRoute!.routeLongName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Route ID: ${_selectedRoute!.routeId}'),
                                Text(
                                  'Associated Trips: ${_selectedRoute!.trips.length}',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._selectedRoute!.trips.map((trip) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ExpansionTile(
                              title: Text('Trip ID: ${trip.tripId}'),
                              subtitle: Text(
                                'Shape ID: ${trip.shapeId ?? "None"} | ${trip.stopTimes.length} Stops',
                              ),
                              children: trip.stopTimes.map((st) {
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 12,
                                    child: Text(
                                      '${st.stopSequence}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                  title: Text(st.stopName),
                                  subtitle: Text('Stop ID: ${st.stopId}'),
                                );
                              }).toList(),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
