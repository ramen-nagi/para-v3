import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePageResetPassword extends StatefulWidget {
  const ProfilePageResetPassword({super.key});
  @override
  State<ProfilePageResetPassword> createState() =>
      _ProfilePageResetPasswordState();
}

class _ProfilePageResetPasswordState extends State<ProfilePageResetPassword> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  StreamSubscription<AuthState>? _subscription;
  bool _recovery = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event == AuthChangeEvent.passwordRecovery && mounted)
        setState(() => _recovery = true);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (_email.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: 'para://auth-callback',
      );
      if (mounted) _show('Password reset email sent.');
    } on AuthException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updatePassword() async {
    if (_password.text.length < 6 || _password.text != _confirm.text) {
      _show('Use matching passwords with at least 6 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (mounted) Navigator.pop(context);
    } on AuthException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_recovery ? 'Set new password' : 'Reset password'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: _recovery
          ? [
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _updatePassword,
                child: const Text('Update password'),
              ),
            ]
          : [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _requestReset,
                child: const Text('Send reset email'),
              ),
            ],
    ),
  );
}
