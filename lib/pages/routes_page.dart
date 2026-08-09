import 'package:flutter/material.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'routes_page_map.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  final SearchController _searchController = SearchController();
  final ScrollController _scrollController = ScrollController();

  VehicleType _selectedType = VehicleType.bus;

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

  List<RoutesModel> _getFilteredRoutes() {
    final allRoutes = GtfsNetworkService.instance.routesMap.values.toList();
    return allRoutes.where((r) => r.vehicleType == _selectedType).toList();
  }

  List<RoutesModel> _getRouteSuggestions(String query) {
    final allRoutes = GtfsNetworkService.instance.routesMap.values.toList();
    final tokens = query
        .toLowerCase()
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      return allRoutes.take(15).toList();
    }

    return allRoutes.where((route) {
      final nameLower = route.routeLongName.toLowerCase();
      return tokens.every((token) => nameLower.contains(token));
    }).toList();
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

  Widget _buildRouteTile(RoutesModel route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: Icon(_getIconForType(route.vehicleType)),
        title: Text(route.routeLongName),
        subtitle: Text(
          '${route.trips.length} direction trips',
        ),
        onTap: () {
          if (_searchController.isOpen) {
            _searchController.closeView(route.routeLongName);
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RoutesPageMap(route: route),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRouteListContent(
    GtfsNetworkService service,
    List<RoutesModel> allCategoryRoutes,
    List<RoutesModel> visibleRoutes,
  ) {
    if (service.isDownloading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allCategoryRoutes.isEmpty) {
      return const Center(
        child: Text('No routes available for this mode.'),
      );
    }

    final bool hasMoreItems = _displayedCount < allCategoryRoutes.length;

    return ListView.builder(
      controller: _scrollController,
      itemCount: visibleRoutes.length + (hasMoreItems ? 1 : 0),
      itemBuilder: (context, index) {
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
              barHintText: 'Search routes',
              suggestionsBuilder: (context, controller) {
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
                  _buildTabItem(VehicleType.bus, Icons.directions_bus),
                  _buildTabItem(VehicleType.jeep, Icons.airport_shuttle),
                  _buildTabItem(VehicleType.train, Icons.train),
                  _buildTabItem(VehicleType.tricycle, Icons.pedal_bike),
                  _buildTabItem(VehicleType.uvExpress, Icons.directions_car),
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

  Widget _buildTabItem(VehicleType type, IconData icon) {
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
