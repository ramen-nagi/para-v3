import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePageSignUp extends StatefulWidget {
  const ProfilePageSignUp({super.key});
  @override State<ProfilePageSignUp> createState() => _ProfilePageSignUpState();
}

class _ProfilePageSignUpState extends State<ProfilePageSignUp> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  @override void dispose() { _email.dispose(); _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) { _show('Use a valid email and a password with at least 6 characters.'); return; }
    if (_password.text != _confirm.text) { _show('Passwords do not match.'); return; }
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client.auth.signUp(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      _show(response.session == null ? 'Check your email to confirm your account.' : 'Account created.');
      Navigator.pop(context);
    } on AuthException catch (error) { _show(error.message); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  void _show(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      FilledButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Creating account...' : 'Sign up')),
    ]),
  );
}
