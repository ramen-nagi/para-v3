import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/module/profile_item_section.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/pages/profile_page_privacy_policy.dart';
import 'package:para_v3/pages/profile_page_terms_of_service.dart';
import 'package:para_v3/pages/profile_page_about.dart';
import 'package:para_v3/pages/profile_page_address_search_history.dart';
import 'package:para_v3/pages/profile_page_change_email.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';
import 'package:para_v3/pages/reports_page.dart';
import 'package:para_v3/pages/route_suggestion_page.dart';
import 'package:para_v3/pages/profile_page_saved_address.dart';
import 'package:para_v3/pages/profile_page_recent_commutes.dart';
import 'package:para_v3/services/fare_calculator_service.dart';
import 'package:para_v3/services/commute_preferences_service.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/raptor_pathfinding_service.dart';

class ProfilePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<Journey> onRecentCommuteSelected;

  const ProfilePage({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.onRecentCommuteSelected,
  });
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  bool _isDiscounted = false;
  bool _isPenalizeTricycle = false;
  bool _isPenalizeTrain = false;
  bool _isPenalizeJeep = false;
  bool _isPenalizeEjeep = false;
  bool _isPenalizeBus = false;
  bool _isPenalizeUvExpress = false;

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
      _isPenalizeTricycle = preferences.isPenalized(VehicleType.tricycle);
      _isPenalizeTrain = preferences.isPenalized(VehicleType.train);
      _isPenalizeJeep = preferences.isPenalized(VehicleType.jeep);
      _isPenalizeEjeep = preferences.isPenalized(VehicleType.ejeep);
      _isPenalizeBus = preferences.isPenalized(VehicleType.bus);
      _isPenalizeUvExpress = preferences.isPenalized(VehicleType.uvExpress);
    });
  }

  Future<void> _setVehiclePreference(
    VehicleType type,
    bool penalized,
  ) async {
    setState(() {
      switch (type) {
        case VehicleType.tricycle:
          _isPenalizeTricycle = penalized;
          break;
        case VehicleType.train:
          _isPenalizeTrain = penalized;
          break;
        case VehicleType.jeep:
          _isPenalizeJeep = penalized;
          break;
        case VehicleType.ejeep:
          _isPenalizeEjeep = penalized;
          break;
        case VehicleType.bus:
          _isPenalizeBus = penalized;
          break;
        case VehicleType.uvExpress:
          _isPenalizeUvExpress = penalized;
          break;
        case VehicleType.unknown:
        case VehicleType.walk:
          break;
      }
    });
    await CommutePreferencesService.instance.setPenalized(type, penalized);
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

  void _openRecentCommutes() {
    _open(
      ProfilePageRecentCommutes(
        onCommuteSelected: widget.onRecentCommuteSelected,
      ),
    );
  }

  Future<void> _verifyCurrentPasswordAndChange() async {
    final user = _user;
    if (user?.email == null) return;

    final currentPassword = await showDialog<String>(
      context: context,
      builder: (_) => const _CurrentPasswordDialog(),
    );
    if (!mounted || currentPassword == null || currentPassword.isEmpty) return;

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: user!.email!,
        password: currentPassword,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _open(const ProfilePageResetPassword(changePasswordOnly: true));
        }
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password verification failed: ${error.message}'),
        ),
      );
    }
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
          icon: Icons.dark_mode_outlined,
          label: 'Dark Mode',
          value: widget.isDarkMode,
          onChanged: widget.onDarkModeChanged,
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
          label: 'Avoid Tricycle',
          value: _isPenalizeTricycle,
          onChanged: (value) =>
              _setVehiclePreference(VehicleType.tricycle, value),
        ),
        _buildSwitchTab(
          icon: Icons.train,
          label: 'Avoid Train',
          value: _isPenalizeTrain,
          onChanged: (value) => _setVehiclePreference(VehicleType.train, value),
        ),
        _buildSwitchTab(
          icon: Icons.airport_shuttle,
          label: 'Avoid Jeep',
          value: _isPenalizeJeep,
          onChanged: (value) => _setVehiclePreference(VehicleType.jeep, value),
        ),
        _buildSwitchTab(
          icon: Icons.electric_rickshaw,
          label: 'Avoid E-Jeep',
          value: _isPenalizeEjeep,
          onChanged: (value) =>
              _setVehiclePreference(VehicleType.ejeep, value),
        ),
        _buildSwitchTab(
          icon: Icons.directions_bus,
          label: 'Avoid Bus',
          value: _isPenalizeBus,
          onChanged: (value) => _setVehiclePreference(VehicleType.bus, value),
        ),
        _buildSwitchTab(
          icon: Icons.directions_car,
          label: 'Avoid UV Express',
          value: _isPenalizeUvExpress,
          onChanged: (value) =>
              _setVehiclePreference(VehicleType.uvExpress, value),
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
          onTap: () => _open(const ProfilePrivacyPolicyPage()),
        ),
        ProfileTabs(
          icon: Icons.description_outlined,
          label: 'Terms of Service',
          onTap: () => _open(
            const ProfilePageTermsOfService(),
          ),
        ),
        ProfileTabs(
          icon: Icons.help_outline,
          label: 'Help and Support',
          onTap: () => _open(
            const ProfilePageAbout(title: 'Help and Support'),
          ),
        ),
        ProfileTabs(
          icon: Icons.auto_stories_outlined,
          label: 'Para Lore',
          onTap: () => _open(
            const ProfilePageAbout(title: 'Para Lore'),
          ),
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
            onTap: () => _open(const ProfilePageAddressSearchHistory()),
          ),
          ProfileTabs(
            icon: Icons.route_outlined,
            label: 'Recent Commutes',
            onTap: _openRecentCommutes,
          ),
          ProfileTabs(
            icon: Icons.bookmark_outline,
            label: 'Saved Addresses',
            onTap: () => _open(const SavedAddressesPage()),
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
            onTap: () => _open(const ProfilePageChangeEmail()),
          ),
          ProfileTabs(
            icon: Icons.lock_reset,
            label: 'Change Password',
            onTap: _verifyCurrentPasswordAndChange,
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
            icon: Icons.history,
            label: 'Address Search History',
            onTap: () => _open(const ProfilePageAddressSearchHistory()),
          ),
          ProfileTabs(
            icon: Icons.route_outlined,
            label: 'Recent Commutes',
            onTap: _openRecentCommutes,
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

class _CurrentPasswordDialog extends StatefulWidget {
  const _CurrentPasswordDialog();

  @override
  State<_CurrentPasswordDialog> createState() => _CurrentPasswordDialogState();
}

class _CurrentPasswordDialogState extends State<_CurrentPasswordDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify your password'),
      content: TextField(
        controller: _passwordController,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Current password',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_passwordController.text),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
