import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/module/route_suggestion_button.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';

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
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() => _user = data.session?.user);
    });
  }

  @override
  void dispose() { _authSubscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.account_circle, size: 72),
          Center(child: Text(user?.email ?? 'You are browsing as a guest.')),
          const SizedBox(height: 20),
          if (user == null) ...[
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePageSignIn())),
              child: const Text('Sign in'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePageSignUp())),
              child: const Text('Create account'),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePageResetPassword())),
              icon: const Icon(Icons.lock_reset), label: const Text('Reset password'),
            ),
            FilledButton.icon(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout), label: const Text('Sign out'),
            ),
          ],
          const SizedBox(height: 24),
          const RouteSuggestionButton(),
        ],
      ),
    );
  }
}
