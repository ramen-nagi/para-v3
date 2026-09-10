import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:para_v3/module/auth_page_layout.dart';
import 'package:para_v3/module/universal_alert_dialog.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_verify_otp.dart';
import 'package:para_v3/services/auth_service.dart';

class ProfilePageSignUp extends StatefulWidget {
  const ProfilePageSignUp({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ProfilePageSignUp> createState() => _ProfilePageSignUpState();
}

class _ProfilePageSignUpState extends State<ProfilePageSignUp> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;

  AuthService get _auth => widget.authService ?? SupabaseAuthService.instance;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = normalizeEmail(_email.text);
    if (!isValidEmail(email)) {
      _show('Enter a valid email address.');
      return;
    }
    if (!isStrongPassword(_password.text)) {
      _show(passwordRequirementsMessage);
      return;
    }
    if (_password.text != _confirm.text) {
      _show('Passwords do not match.');
      return;
    }

    TextInput.finishAutofillContext();
    setState(() => _loading = true);
    try {
      final outcome = await _auth.signUp(
        email: email,
        password: _password.text,
      );
      if (!mounted) return;
      if (outcome == SignUpOutcome.possiblyExisting) {
        setState(() => _loading = false);
        await _showExistingAccountHelp();
        return;
      }
      if (outcome == SignUpOutcome.verificationRequired) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ProfilePageVerifyOtp(
              email: email,
              purpose: EmailOtpPurpose.signup,
              title: 'Confirm your email',
              description: 'Enter the code we sent to',
              authService: _auth,
            ),
          ),
        );
        return;
      }
      _show('Account created successfully.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _show(
        authErrorMessage(error, fallback: 'Unable to create your account.'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showExistingAccountHelp() async {
    await UniversalAlertDialog.show(
      context: context,
      title: 'Check your account',
      content:
          'We could not create a new account or send a confirmation code. '
          'If you have registered before, sign in or reset your password.',
      primaryButtonText: 'Sign in',
      onPrimaryPressed: () => _replaceWith(
        ProfilePageSignIn(authService: _auth),
      ),
      secondaryButtonText: 'Reset password',
      onSecondaryPressed: () => _replaceWith(
        ProfilePageResetPassword(authService: _auth),
      ),
    );
  }

  void _replaceWith(Widget page) {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _passwordDecoration(String label) => authFieldDecoration(
    label: label,
    icon: Icons.lock_outline_rounded,
    suffixIcon: IconButton(
      tooltip: _showPassword ? 'Hide password' : 'Show password',
      onPressed: () => setState(() => _showPassword = !_showPassword),
      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
    ),
  );

  @override
  Widget build(BuildContext context) => AuthPageLayout(
    appBarTitle: 'Create account',
    icon: Icons.person_add_alt_1_rounded,
    title: 'Welcome to Para!',
    subtitle:
        'Create an account to save addresses, keep a record of your commutes, '
        'and enjoy higher app usage limits.',
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
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => setState(() {}),
            decoration: _passwordDecoration('Password'),
          ),
          const SizedBox(height: 12),
          PasswordRequirements(password: _password.text),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_loading) _submit();
            },
            decoration: _passwordDecoration('Confirm password'),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Sign up',
            loadingLabel: 'Creating account...',
            loading: _loading,
            onPressed: _submit,
            icon: Icons.person_add_alt_1_rounded,
          ),
        ],
      ),
    ),
    footer: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Already have an account?'),
        TextButton(
          onPressed: _loading
              ? null
              : () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePageSignIn(authService: _auth),
                  ),
                ),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
}
