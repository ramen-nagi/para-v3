import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/module/profile_item_section.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';
import 'package:para_v3/pages/reports_page.dart';
import 'package:para_v3/pages/route_suggestion_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<AuthState>? _authSubscription;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = Supabase.instance.client.auth.currentUser;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (mounted) setState(() => _user = data.session?.user);
    });
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
            Icon(Icons.explore_outlined, size: 42, color: theme.colorScheme.primary),
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

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final List<ProfileTabs> authenticationItems;
    if (user == null) {
      authenticationItems = [
        ProfileTabs(
          icon: Icons.login,
          label: 'Sign in',
          onTap: () => _open(const ProfilePageSignIn()),
        ),
        ProfileTabs(
          icon: Icons.person_add_outlined,
          label: 'Create account',
          onTap: () => _open(const ProfilePageSignUp()),
        ),
      ];
    } else {
      authenticationItems = [
        ProfileTabs(
          icon: Icons.lock_reset,
          label: 'Reset password',
          onTap: () => _open(const ProfilePageResetPassword()),
        ),
        ProfileTabs(
          icon: Icons.logout,
          label: 'Sign out',
          onTap: () => Supabase.instance.client.auth.signOut(),
        ),
      ];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user == null) ...[
            _buildGuestAuthPrompt(),
            const SizedBox(height: 16),
          ]
          else
            ProfileSection(
              title: 'Profile Identity',
              items: [
                ProfileTabs(
                  icon: Icons.email_outlined,
                  label: user.email ?? 'No email address',
                ),
                const ProfileTabs(
                  icon: Icons.verified_user_outlined,
                  label: 'Signed in',
                ),
              ],
            ),
          ProfileSection(
            title: 'App Preferences',
            items: [
              ProfileTabs(
                icon: Icons.palette_outlined,
                label: 'Theme',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.language,
                label: 'Language',
                onTap: _comingSoon,
              ),
            ],
          ),
          ProfileSection(
            title: 'Saved Data',
            items: [
              ProfileTabs(
                icon: Icons.home_outlined,
                label: 'Home',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.school_outlined,
                label: 'School',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.work_outline,
                label: 'Work',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.history,
                label: 'Recent addresses',
                onTap: _comingSoon,
              ),
            ],
          ),
          ProfileSection(
            title: 'Reports and Contributions',
            items: [
              ProfileTabs(
                icon: Icons.report_problem_outlined,
                label: 'Submit a report',
                onTap: () => _open(const ReportsPage()),
              ),
              ProfileTabs(
                icon: Icons.ios_share_rounded,
                label: 'Suggest a route',
                onTap: () => _open(const RouteSuggestionPage()),
              ),
            ],
          ),
          ProfileSection(
            title: 'Privacy and Support',
            items: [
              ProfileTabs(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy policy',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.description_outlined,
                label: 'Terms of service',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.help_outline,
                label: 'Help and support',
                onTap: _comingSoon,
              ),
            ],
          ),
          ProfileSection(
            title: 'About Para',
            items: [
              ProfileTabs(
                icon: Icons.info_outline,
                label: 'About Para',
                onTap: _comingSoon,
              ),
              ProfileTabs(
                icon: Icons.app_settings_alt,
                label: 'App version',
                onTap: _comingSoon,
              ),
            ],
          ),
          ProfileSection(
            title: 'Authentication',
            items: authenticationItems,
          ),
        ],
      ),
    );
  }
}
