import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/module/offline_modal.dart';
import 'pages/commute_page.dart';
import 'pages/routes_page.dart';
import 'pages/profile_page.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  GtfsNetworkService.instance.initializeAndSync();

  runApp(const ParaApp());
}

class ParaApp extends StatelessWidget {
  const ParaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: offlineScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Para Metro Manila Commute App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const OfflineConnectivityGate(child: MainPage()),
    );
  }
}

class OfflineConnectivityGate extends StatefulWidget {
  final Widget child;

  const OfflineConnectivityGate({super.key, required this.child});

  @override
  State<OfflineConnectivityGate> createState() =>
      _OfflineConnectivityGateState();
}

class _OfflineConnectivityGateState extends State<OfflineConnectivityGate> {
  late final InternetConnection _internetConnection;
  StreamSubscription<InternetStatus>? _statusSubscription;
  bool _offlineModalShownForOutage = false;
  int _statusCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _internetConnection = InternetConnection.createInstance(
      checkInterval: const Duration(seconds: 10),
    );
    _statusSubscription = _internetConnection.onStatusChange.listen(
      _handleInternetStatus,
    );
  }

  void _handleInternetStatus(InternetStatus status) {
    if (status == InternetStatus.connected) {
      _statusCheckGeneration++;
      _offlineModalShownForOutage = false;
      offlineScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      return;
    }

    if (_offlineModalShownForOutage || !mounted) return;
    final generation = ++_statusCheckGeneration;
    _confirmOfflineStatus(generation);
  }

  Future<void> _confirmOfflineStatus(int generation) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted || generation != _statusCheckGeneration) return;

    final hasInternet = await _internetConnection.hasInternetAccess;
    if (!mounted || generation != _statusCheckGeneration || hasInternet) return;

    _offlineModalShownForOutage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OfflineModal.show(context);
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    CommutePage(),
    RoutesPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Commute'),
          BottomNavigationBarItem(icon: Icon(Icons.train), label: 'Routes'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
