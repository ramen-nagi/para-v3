import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/profile_sync_service.dart';
import 'pages/commute_page.dart';
import 'pages/auth_page.dart';
import 'pages/routes_page.dart';
import 'pages/profile_page.dart';

final paraNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  GtfsNetworkService.instance.initializeAndSync();
  unawaited(ProfileSyncService.instance.start());

  runApp(const ParaApp());
}

class ParaApp extends StatelessWidget {
  const ParaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: paraNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Para',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  StreamSubscription<AuthState>? _authSubscription;
  bool _showingRecovery = false;

  final List<Widget> _pages = const [
    CommutePage(),
    RoutesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          _openPasswordRecovery();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Authentication state error: $error');
      },
    );
  }

  void _openPasswordRecovery() {
    if (_showingRecovery) return;
    _showingRecovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = paraNavigatorKey.currentState;
      if (navigator == null) {
        _showingRecovery = false;
        return;
      }
      await navigator.push(
        MaterialPageRoute(
          builder: (context) => const UpdatePasswordPage(isRecovery: true),
        ),
      );
      _showingRecovery = false;
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

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
