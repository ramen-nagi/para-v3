import 'dart:async';
import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/module/universal_alert_dialog.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/recents_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';
import 'routes_page_map.dart';

IconData getIconForType(VehicleType type) {
  // TODO: Make custom SVG for each vehicle type
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

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

enum _RouteTab { favorites, bus, jeep, train, tricycle, uvExpress }

extension on _RouteTab {
  VehicleType? get vehicleType {
    switch (this) {
      case _RouteTab.favorites:
        return null;
      case _RouteTab.bus:
        return VehicleType.bus;
      case _RouteTab.jeep:
        return VehicleType.jeep;
      case _RouteTab.train:
        return VehicleType.train;
      case _RouteTab.tricycle:
        return VehicleType.tricycle;
      case _RouteTab.uvExpress:
        return VehicleType.uvExpress;
    }
  }
}

class _RoutesPageState extends State<RoutesPage> {
  final SearchController _searchController = SearchController();
  final ScrollController _scrollController = ScrollController();

  _RouteTab _selectedTab = _RouteTab.bus;
  final Set<String> _favoriteRouteIds = <String>{};
  StreamSubscription<AuthState>? _authSubscription;

  static const int _pageSize = 10;
  int _displayedCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _loadFavoriteRoutes();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;
        if (data.session == null) {
          setState(() => _favoriteRouteIds.clear());
        } else {
          _loadFavoriteRoutes();
        }
      },
    );
    GtfsNetworkService.instance.addListener(_onServiceUpdate);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadFavoriteRoutes() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final favoriteIds = await RecentsService.instance.getFavoriteRouteIds();
    if (!mounted) return;
    setState(() {
      _favoriteRouteIds
        ..clear()
        ..addAll(favoriteIds);
    });
  }

  @override
  void dispose() {
    GtfsNetworkService.instance.removeListener(_onServiceUpdate);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _authSubscription?.cancel();
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
    final filtered = _selectedTab == _RouteTab.favorites
        ? allRoutes.where((route) => _favoriteRouteIds.contains(route.routeId))
        : allRoutes.where((route) => route.vehicleType == _selectedTab.vehicleType);
    final routes = filtered.toList();
    if (_selectedTab == _RouteTab.favorites) return routes;

    final favoriteRoutes = routes
        .where((route) => _favoriteRouteIds.contains(route.routeId))
        .toList();
    final otherRoutes = routes
        .where((route) => !_favoriteRouteIds.contains(route.routeId))
        .toList();
    return [...favoriteRoutes, ...otherRoutes];
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

  void _onTabChanged(_RouteTab newTab) {
    if (_selectedTab != newTab) {
      setState(() {
        _selectedTab = newTab;
        _displayedCount = _pageSize;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  Future<void> _toggleFavorite(RoutesModel route) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      await _showAuthenticationPrompt();
      return;
    }
    final isFavorite = !_favoriteRouteIds.contains(route.routeId);
    setState(() {
      if (isFavorite) {
        _favoriteRouteIds.add(route.routeId);
      } else {
        _favoriteRouteIds.remove(route.routeId);
      }
    });
    await RecentsService.instance.setFavoriteRoute(route.routeId, isFavorite);
  }

  Future<void> _showAuthenticationPrompt() async {
    await UniversalAlertDialog.show(
      context: context,
      title: 'Sign in to save routes',
      content: 'Create an account or sign in to favorite routes and access them later.',
      secondaryButtonText: 'Sign in',
      onSecondaryPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfilePageSignIn()),
      ),
      primaryButtonText: 'Create account',
      onPrimaryPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfilePageSignUp()),
      ),
    );
  }

  Widget _buildRouteTile(RoutesModel route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: Icon(getIconForType(route.vehicleType)),
        title: Text(route.routeLongName),
        subtitle: Text(
          '${route.trips.length} direction trips',
        ),
        trailing: IconButton(
          icon: Icon(
            _favoriteRouteIds.contains(route.routeId)
                ? Icons.favorite
                : Icons.favorite_border,
            color: _favoriteRouteIds.contains(route.routeId)
                ? Colors.red
                : null,
          ),
          onPressed: () => _toggleFavorite(route),
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
      final message = _selectedTab == _RouteTab.favorites
          ? 'No favorite routes yet.'
          : 'No routes available for this mode.';
      return Center(child: Text(message));
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
      appBar: const ParaAppBar(title: 'Routes'),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            SizedBox(height: 8),
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
                  _buildTabItem(_RouteTab.favorites, 'Favorites'),
                  _buildTabItem(_RouteTab.bus, 'Bus'),
                  _buildTabItem(_RouteTab.jeep, 'Jeep'),
                  _buildTabItem(_RouteTab.train, 'Train'),
                  _buildTabItem(_RouteTab.tricycle, 'Tricycle'),
                  _buildTabItem(_RouteTab.uvExpress, 'UV Express'),
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

  Widget _buildTabItem(_RouteTab tab, String label) {
    final isSelected = _selectedTab == tab;

    return InkWell(
      onTap: () => _onTabChanged(tab),
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
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

}
