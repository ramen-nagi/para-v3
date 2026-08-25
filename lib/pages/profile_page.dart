import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/module/profile_item_section.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';
import 'package:para_v3/pages/reports_page.dart';
import 'package:para_v3/pages/route_suggestion_page.dart';
import 'package:para_v3/services/fare_calculator_service.dart';
import 'package:para_v3/services/commute_preferences_service.dart';
import 'package:para_v3/services/gtfs_network_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  bool _isDiscounted = false;
  bool _isDarkMode = false;
  bool _includeTricycle = true;
  bool _includeTrain = true;
  bool _includeJeep = true;
  bool _includeBus = true;
  bool _includeUvExpress = true;

  @override
  void initState() {
    super.initState();
    _user = Supabase.instance.client.auth.currentUser;
    _loadFarePreference();
    _loadCommutePreferences();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (mounted) setState(() => _user = data.session?.user);
    });
  }

  Future<void> _loadFarePreference() async {
    final fareService = FareCalculatorService.instance;
    await fareService.initialize();
    if (!mounted) return;
    setState(() => _isDiscounted = fareService.useDiscountedFare);
  }

  Future<void> _loadCommutePreferences() async {
    final preferences = CommutePreferencesService.instance;
    await preferences.initialize();
    if (!mounted) return;
    setState(() {
      _includeTricycle = preferences.isEnabled(VehicleType.tricycle);
      _includeTrain = preferences.isEnabled(VehicleType.train);
      _includeJeep = preferences.isEnabled(VehicleType.jeep);
      _includeBus = preferences.isEnabled(VehicleType.bus);
      _includeUvExpress = preferences.isEnabled(VehicleType.uvExpress);
    });
  }

  Future<void> _setVehiclePreference(
    VehicleType type,
    bool enabled,
  ) async {
    setState(() {
      switch (type) {
        case VehicleType.tricycle:
          _includeTricycle = enabled;
          break;
        case VehicleType.train:
          _includeTrain = enabled;
          break;
        case VehicleType.jeep:
          _includeJeep = enabled;
          break;
        case VehicleType.bus:
          _includeBus = enabled;
          break;
        case VehicleType.uvExpress:
          _includeUvExpress = enabled;
          break;
        case VehicleType.unknown:
        case VehicleType.walk:
          break;
      }
    });
    await CommutePreferencesService.instance.setEnabled(type, enabled);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This feature is coming soon.')),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildGuestAuthPrompt() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.explore_outlined,
              size: 42,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Make every commute easier',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in or create an account to save places, report issues, and help improve Para.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _open(const ProfilePageSignUp()),
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _open(const ProfilePageSignIn()),
                    child: const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ProfileTabs _buildSwitchTab({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ProfileTabs(
      icon: icon,
      label: label,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  ProfileSection _buildAppSettingsSection() {
    return ProfileSection(
      title: 'App Settings',
      items: [
        _buildSwitchTab(
          // TODO: Make the app in dark mode
          icon: Icons.dark_mode_outlined,
          label: 'Dark Mode',
          value: _isDarkMode,
          onChanged: (value) => setState(() => _isDarkMode = value),
        ),
      ],
    );
  }

  ProfileSection _buildCommuteSettingsSection() {
    return ProfileSection(
      title: 'Commute Settings',
      items: [
        _buildSwitchTab(
          icon: Icons.confirmation_number_outlined,
          label: 'Discounted Fare',
          value: _isDiscounted,
          onChanged: (value) async {
            setState(() => _isDiscounted = value);
            await FareCalculatorService.instance.setDiscountedFare(value);
          },
        ),
        _buildSwitchTab(
          icon: Icons.pedal_bike,
          label: 'Tricycle',
          value: _includeTricycle,
          onChanged: (value) => _setVehiclePreference(VehicleType.tricycle, value),
        ),
        _buildSwitchTab(
          icon: Icons.train,
          label: 'Train',
          value: _includeTrain,
          onChanged: (value) => _setVehiclePreference(VehicleType.train, value),
        ),
        _buildSwitchTab(
          icon: Icons.airport_shuttle,
          label: 'Jeep',
          value: _includeJeep,
          onChanged: (value) => _setVehiclePreference(VehicleType.jeep, value),
        ),
        _buildSwitchTab(
          icon: Icons.directions_bus,
          label: 'Bus',
          value: _includeBus,
          onChanged: (value) => _setVehiclePreference(VehicleType.bus, value),
        ),
        _buildSwitchTab(
          icon: Icons.directions_car,
          label: 'UV Express',
          value: _includeUvExpress,
          onChanged: (value) => _setVehiclePreference(VehicleType.uvExpress, value),
        ),
      ],
    );
  }

  ProfileSection _buildAboutSection() {
    return ProfileSection(
      title: 'About Para',
      items: [
        ProfileTabs(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Policy',
          onTap: _comingSoon,
        ),
        ProfileTabs(
          icon: Icons.description_outlined,
          label: 'Terms of Service',
          onTap: _comingSoon,
        ),
        ProfileTabs(
          icon: Icons.help_outline,
          label: 'Help and Support',
          onTap: _comingSoon,
        ),
        ProfileTabs(
          icon: Icons.auto_stories_outlined,
          label: 'Para Lore',
          onTap: _comingSoon,
        ),
      ],
    );
  }

  ProfileSection _buildContributeSection() {
    return ProfileSection(
      title: 'Contribute',
      items: [
        ProfileTabs(
          icon: Icons.report_problem_outlined,
          label: 'Report',
          onTap: () => _open(const ReportsPage()),
        ),
        ProfileTabs(
          icon: Icons.ios_share_rounded,
          label: 'Suggest a Route',
          onTap: () => _open(const RouteSuggestionPage()),
        ),
      ],
    );
  }

  List<Widget> _buildAuthenticatedContent(User user) {
    return [
      // TODO: Make this prettier
      Text(
        user.email!,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      SizedBox(height: 10),
      const Divider(),
      ProfileSection(
        title: 'User Information',
        items: [
          ProfileTabs(
            icon: Icons.history,
            label: 'Address Search History',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            icon: Icons.route_outlined,
            label: 'Recent Commutes',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            icon: Icons.bookmark_outline,
            label: 'Saved Addresses',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            icon: Icons.sync,
            label: 'Sync Data',
            onTap: _comingSoon,
          ),
        ],
      ),
      _buildAppSettingsSection(),
      _buildCommuteSettingsSection(),
      _buildContributeSection(),
      _buildAboutSection(),
      ProfileSection(
        title: 'Account',
        items: [
          ProfileTabs(
            icon: Icons.email_outlined,
            label: 'Change Email',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            icon: Icons.lock_reset,
            label: 'Change Password',
            onTap: () => _open(const ProfilePageResetPassword()),
          ),
          ProfileTabs(
            icon: Icons.delete_outline,
            label: 'Delete Account',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            icon: Icons.logout,
            label: 'Sign Out',
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildGuestContent() {
    return [
      _buildGuestAuthPrompt(),
      const SizedBox(height: 16),
      ProfileSection(
        title: 'Account',
        items: [
          const ProfileTabs(
            icon: Icons.person_outline,
            label: 'Guest User',
            // TODO: Remove trailing here
          ),
          ProfileTabs(
            icon: Icons.login,
            label: 'Sign In',
            onTap: () => _open(const ProfilePageSignIn()),
          ),
          ProfileTabs(
            icon: Icons.person_add_outlined,
            label: 'Create an Account',
            onTap: () => _open(const ProfilePageSignUp()),
          ),
        ],
      ),
      ProfileSection(
        title: 'My Information',
        items: [
          ProfileTabs(
            // TODO: Add universal alert dialog to print the recent addresses in a listview with option to delete
            icon: Icons.history,
            label: 'Address Search History',
            onTap: _comingSoon,
          ),
          ProfileTabs(
            // TODO: Add universal alert dialog to print the recent addresses in a listview with option to delete
            // TODO: Make it tappable that will then take them to the commute page with enum activeLeg
            icon: Icons.route_outlined,
            label: 'Recent Commutes',
            onTap: _comingSoon,
          ),
        ],
      ),
      _buildAppSettingsSection(),
      _buildCommuteSettingsSection(),
      _buildAboutSection(),
      _buildContributeSection(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final List<Widget> content;
    if (user == null) {
      content = _buildGuestContent();
    } else {
      content = _buildAuthenticatedContent(user);
    }
    return Scaffold(
      appBar: const ParaAppBar(title: 'Profile'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: content,
      ),
    );
  }
}
