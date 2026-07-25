import 'package:flutter/material.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  final SearchController _searchController = SearchController();
  final ScrollController _scrollController = ScrollController();

  VehicleType _selectedType = VehicleType.bus;
  RouteModel? _selectedRoute;

  static const int _pageSize = 10;
  int _displayedCount = _pageSize;

  @override
  void initState() {
    super.initState();
    GtfsNetworkService.instance.addListener(_onServiceUpdate);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    GtfsNetworkService.instance.removeListener(_onServiceUpdate);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    setState(() {});
  }

  void _onScroll() {
    // Check if user scrolled near the bottom of the current 10 items
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreRoutes();
    }
  }

  void _loadMoreRoutes() {
    final totalFiltered = _getFilteredRoutes().length;
    if (_displayedCount < totalFiltered) {
      setState(() {
        _displayedCount = (_displayedCount + _pageSize).clamp(0, totalFiltered);
      });
    }
  }

  List<RouteModel> _getFilteredRoutes() {
    final allRoutes = GtfsNetworkService.instance.routesMap.values.toList();
    return allRoutes.where((r) => r.vehicleType == _selectedType).toList();
  }

  void _onTabChanged(VehicleType newType) {
    if (_selectedType != newType) {
      setState(() {
        _selectedType = newType;
        _displayedCount = _pageSize;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  List<RouteModel> _getRouteSuggestions(String query) {
    final allRoutes = GtfsNetworkService.instance.routesMap.values.toList();

    final tokens = query
        .toLowerCase()
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      return allRoutes.take(15).toList();
    }

    return allRoutes.where((route) {
      final nameLower = route.routeLongName.toLowerCase();
      return tokens.every((token) => nameLower.contains(token));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final service = GtfsNetworkService.instance;
    final allCategoryRoutes = _getFilteredRoutes();
    final visibleRoutes = allCategoryRoutes.take(_displayedCount).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            SearchAnchor.bar(
              searchController: _searchController,
              barHintText: 'Search routes (e.g., Philcoa UP)...',
              suggestionsBuilder:
                  (BuildContext context, SearchController controller) {
                    if (!service.isLoaded) {
                      return const [
                        ListTile(
                          leading: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          title: Text('Syncing database...'),
                        ),
                      ];
                    }

                    final suggestions = _getRouteSuggestions(controller.text);

                    if (suggestions.isEmpty) {
                      return const [
                        ListTile(title: Text('No routes found')),
                      ];
                    }

                    return suggestions
                        .map((route) => _buildRouteTile(route))
                        .toList();
                  },
            ),

            const SizedBox(height: 12),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabItem(
                    'Bus',
                    VehicleType.bus,
                    Icons.directions_bus,
                  ),
                  _buildTabItem(
                    'Jeep',
                    VehicleType.jeep,
                    Icons.airport_shuttle,
                  ),
                  _buildTabItem(
                    'Train',
                    VehicleType.train,
                    Icons.train,
                  ),
                  _buildTabItem(
                    'Tricycle',
                    VehicleType.tricycle,
                    Icons.pedal_bike,
                  ),
                  _buildTabItem(
                    'UV Express',
                    VehicleType.uvExpress,
                    Icons.directions_car,
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            Expanded(
              child: _buildRouteListContent(
                service,
                allCategoryRoutes,
                visibleRoutes,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteTile(RouteModel route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: Icon(_getIconForType(route.vehicleType)),
        title: Text(route.routeLongName),
        subtitle: Text(
          'ID: ${route.routeId} • ${route.trips.length} direction trips',
        ),
        onTap: () {
          setState(() {
            _selectedRoute = route;
          });

          // Close search view if open
          if (_searchController.isOpen) {
            _searchController.closeView(route.routeLongName);
          }

          debugPrint('Tapped Route: ${route.routeLongName} (${route.routeId})');
        },
      ),
    );
  }

  Widget _buildRouteListContent(
    GtfsNetworkService service,
    List<RouteModel> allCategoryRoutes,
    List<RouteModel> visibleRoutes,
  ) {
    // State 1: Still downloading or syncing database
    if (service.isDownloading) {
      return const Center(child: CircularProgressIndicator());
    }

    // State 2: No routes match the selected vehicle category
    if (allCategoryRoutes.isEmpty) {
      return const Center(
        child: Text('No routes available for this mode.'),
      );
    }

    // State 3: Render paginated list
    final bool hasMoreItems = _displayedCount < allCategoryRoutes.length;

    return ListView.builder(
      controller: _scrollController,
      itemCount: visibleRoutes.length + (hasMoreItems ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading spinner at the bottom when fetching next page
        if (index == visibleRoutes.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final route = visibleRoutes[index];
        return _buildRouteTile(route);
      },
    );
  }

  Widget _buildTabItem(String label, VehicleType type, IconData icon) {
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: () => _onTabChanged(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(VehicleType type) {
    switch (type) {
      case VehicleType.bus:
        return Icons.directions_bus;
      case VehicleType.jeep:
        return Icons.airport_shuttle;
      case VehicleType.train:
        return Icons.train;
      case VehicleType.tricycle:
        return Icons.pedal_bike;
      case VehicleType.uvExpress:
        return Icons.directions_car;
      default:
        return Icons.alt_route;
    }
  }
}
