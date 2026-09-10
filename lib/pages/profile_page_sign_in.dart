import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:para_v3/module/auth_page_layout.dart';
import 'package:para_v3/services/auth_service.dart';
import 'profile_page_reset_password.dart';
import 'profile_page_sign_up.dart';

class ProfilePageSignIn extends StatefulWidget {
  const ProfilePageSignIn({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ProfilePageSignIn> createState() => _ProfilePageSignInState();
}

class _ProfilePageSignInState extends State<ProfilePageSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;

  AuthService get _auth => widget.authService ?? SupabaseAuthService.instance;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isValidEmail(_email.text) || _password.text.isEmpty) {
      _show('Enter a valid email and password.');
      return;
    }
    TextInput.finishAutofillContext();
    setState(() => _loading = true);
    try {
      await _auth.signIn(email: _email.text, password: _password.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _show(authErrorMessage(error, fallback: 'Unable to sign in.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AuthPageLayout(
    appBarTitle: 'Sign in',
    icon: Icons.directions_bus_rounded,
    title: 'Welcome back',
    subtitle:
        'Sign in to access places, trips, and preferences across devices.',
    form: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: authFieldDecoration(
              label: 'Email address',
              hint: 'you@example.com',
              icon: Icons.mail_outline_rounded,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) {
              if (!_loading) _submit();
            },
            decoration: authFieldDecoration(
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfilePageResetPassword(authService: _auth),
                      ),
                    ),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 4),
          AuthPrimaryButton(
            label: 'Sign in',
            loadingLabel: 'Signing in...',
            loading: _loading,
            onPressed: _submit,
            icon: Icons.login_rounded,
          ),
        ],
      ),
    ),
    footer: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('New to Para?'),
        TextButton(
          onPressed: _loading
              ? null
              : () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePageSignUp(authService: _auth),
                  ),
                ),
          child: const Text('Create account'),
        ),
      ],
    ),
  );
}
