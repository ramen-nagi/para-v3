import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:para_v3/module/auth_page_layout.dart';
import 'package:para_v3/pages/profile_page_verify_otp.dart';
import 'package:para_v3/services/auth_service.dart';

class ProfilePageResetPassword extends StatefulWidget {
  const ProfilePageResetPassword({
    super.key,
    this.changePasswordOnly = false,
    this.authService,
  });

  final bool changePasswordOnly;
  final AuthService? authService;

  @override
  State<ProfilePageResetPassword> createState() =>
      _ProfilePageResetPasswordState();
}

class _ProfilePageResetPasswordState extends State<ProfilePageResetPassword> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _settingPassword = false;
  bool _loading = false;
  bool _showPassword = false;

  AuthService get _auth => widget.authService ?? SupabaseAuthService.instance;

  @override
  void initState() {
    super.initState();
    _settingPassword = widget.changePasswordOnly;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final email = normalizeEmail(_email.text);
    if (!isValidEmail(email)) {
      _show('Enter a valid email address.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.requestPasswordReset(email);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfilePageVerifyOtp(
            email: email,
            purpose: EmailOtpPurpose.recovery,
            title: 'Verify reset code',
            description: 'If an account exists, a code was sent to',
            authService: _auth,
            onVerified: () async {
              if (!mounted) return;
              Navigator.of(context).pop();
              setState(() => _settingPassword = true);
            },
          ),
        ),
      );
    } catch (error) {
      _show(
        authErrorMessage(error, fallback: 'Unable to request a reset code.'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updatePassword() async {
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
      await _auth.updatePassword(_password.text);
      if (!mounted) return;
      _show('Password updated successfully.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _show(
        authErrorMessage(error, fallback: 'Unable to update the password.'),
      );
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
    appBarTitle: _settingPassword
        ? (widget.changePasswordOnly ? 'Change password' : 'Set new password')
        : 'Reset password',
    icon: _settingPassword ? Icons.password_rounded : Icons.lock_reset_rounded,
    title: _settingPassword ? 'Choose a new password' : 'Recover your account',
    subtitle: _settingPassword
        ? 'Make it memorable, unique, and difficult for others to guess.'
        : 'We will send a $emailOtpLength-digit verification code to your account email.',
    form: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _settingPassword ? _passwordFields() : _emailFields(),
      ),
    ),
  );

  List<Widget> _emailFields() => [
    const SizedBox(height: 16),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.email],
      onSubmitted: (_) {
        if (!_loading) _requestReset();
      },
      decoration: authFieldDecoration(
        label: 'Email address',
        hint: 'you@example.com',
        icon: Icons.mail_outline_rounded,
      ),
    ),
    const SizedBox(height: 20),
    AuthPrimaryButton(
      label: 'Send reset code',
      loadingLabel: 'Sending code...',
      loading: _loading,
      onPressed: _requestReset,
      icon: Icons.mark_email_read_outlined,
    ),
  ];

  List<Widget> _passwordFields() => [
    TextField(
      controller: _password,
      obscureText: !_showPassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      onChanged: (_) => setState(() {}),
      decoration: _passwordDecoration('New password'),
    ),
    const SizedBox(height: 12),
    PasswordRequirements(password: _password.text),
    const SizedBox(height: 16),
    TextField(
      controller: _confirm,
      obscureText: !_showPassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (!_loading) _updatePassword();
      },
      decoration: _passwordDecoration('Confirm password'),
    ),
    const SizedBox(height: 20),
    AuthPrimaryButton(
      label: 'Update password',
      loadingLabel: 'Updating password...',
      loading: _loading,
      onPressed: _updatePassword,
      icon: Icons.check_rounded,
    ),
  ];

  InputDecoration _passwordDecoration(String label) => authFieldDecoration(
    label: label,
    icon: Icons.lock_outline_rounded,
    suffixIcon: IconButton(
      tooltip: _showPassword ? 'Hide password' : 'Show password',
      onPressed: () => setState(() => _showPassword = !_showPassword),
      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
    ),
  );
}
