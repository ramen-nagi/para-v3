import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePageChangeEmail extends StatefulWidget {
  const ProfilePageChangeEmail({super.key});

  @override
  State<ProfilePageChangeEmail> createState() =>
      _ProfilePageChangeEmailState();
}

class _ProfilePageChangeEmailState extends State<ProfilePageChangeEmail> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentEmail = Supabase.instance.client.auth.currentUser?.email;
    final newEmail = _email.text.trim();

    if (currentEmail == null) return;
    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      _show('Enter a valid email address.');
      return;
    }
    if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
      _show('Enter a different email address.');
      return;
    }
    if (_password.text.isEmpty) {
      _show('Enter your current password.');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: currentEmail,
        password: _password.text,
      );
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );
      if (!mounted) return;
      _show('Check your email to confirm the change.');
      Navigator.pop(context);
    } on AuthException catch (error) {
      _show('Unable to change email: ${error.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ParaAppBar(title: 'Change email'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'New email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: Text(_loading ? 'Changing email...' : 'Change email'),
        ),
      ],
    ),
  );
}
