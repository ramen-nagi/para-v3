import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/services/auth_service.dart';

enum _EmailChangeStep { request, currentCode, newCode }

class ProfilePageChangeEmail extends StatefulWidget {
  const ProfilePageChangeEmail({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ProfilePageChangeEmail> createState() => _ProfilePageChangeEmailState();
}

class _ProfilePageChangeEmailState extends State<ProfilePageChangeEmail> {
  static const _cooldownSeconds = 60;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  _EmailChangeStep _step = _EmailChangeStep.request;
  Timer? _timer;
  int _remaining = 0;
  bool _loading = false;
  bool _showPassword = false;

  AuthService get _auth => widget.authService ?? SupabaseAuthService.instance;
  String get _currentEmail => _auth.currentEmail ?? '';
  String get _newEmail => normalizeEmail(_email.text);

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _requestChange() async {
    final newEmail = _newEmail;
    if (_currentEmail.isEmpty) {
      _show('Your session has expired. Sign in again.');
      return;
    }
    if (!isValidEmail(newEmail)) {
      _show('Enter a valid email address.');
      return;
    }
    if (newEmail == normalizeEmail(_currentEmail)) {
      _show('Enter a different email address.');
      return;
    }
    if (_password.text.isEmpty) {
      _show('Enter your current password.');
      return;
    }

    TextInput.finishAutofillContext();
    setState(() => _loading = true);
    try {
      await _auth.beginEmailChange(
        currentEmail: _currentEmail,
        newEmail: newEmail,
        password: _password.text,
      );
      if (!mounted) return;
      _password.clear();
      _code.clear();
      setState(() => _step = _EmailChangeStep.currentCode);
      _startCooldown();
    } catch (error) {
      _show(
        authErrorMessage(error, fallback: 'Unable to start the email change.'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_code.text.trim().length != emailOtpLength) {
      _show('Enter the $emailOtpLength-digit code from your email.');
      return;
    }
    setState(() => _loading = true);
    try {
      final verificationEmail = _step == _EmailChangeStep.currentCode
          ? _currentEmail
          : _newEmail;
      await _auth.verifyEmailOtp(
        email: verificationEmail,
        token: _code.text,
        purpose: EmailOtpPurpose.emailChange,
      );
      if (!mounted) return;
      if (_step == _EmailChangeStep.currentCode) {
        _code.clear();
        setState(() => _step = _EmailChangeStep.newCode);
      } else {
        _show('Email address updated successfully.');
        Navigator.of(context).pop();
      }
    } catch (error) {
      _show(authErrorMessage(error, fallback: 'Unable to verify the code.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await _auth.resendEmailChange(_newEmail);
      if (!mounted) return;
      _code.clear();
      setState(() => _step = _EmailChangeStep.currentCode);
      _startCooldown();
      _show('New codes were sent. Start again with your current email.');
    } catch (error) {
      _show(authErrorMessage(error, fallback: 'Unable to resend the codes.'));
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
  Widget build(BuildContext context) => Scaffold(
    appBar: const ParaAppBar(title: 'Change email'),
    body: AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _step == _EmailChangeStep.request
            ? _requestFields()
            : _verificationFields(),
      ),
    ),
  );

  List<Widget> _requestFields() => [
    Text('Current email: $_currentEmail'),
    const SizedBox(height: 16),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email],
      decoration: const InputDecoration(
        labelText: 'New email',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _password,
      obscureText: !_showPassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) {
        if (!_loading) _requestChange();
      },
      decoration: InputDecoration(
        labelText: 'Current password',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _showPassword ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _loading ? null : _requestChange,
      child: Text(_loading ? 'Sending codes...' : 'Change email'),
    ),
  ];

  List<Widget> _verificationFields() {
    final checkingCurrent = _step == _EmailChangeStep.currentCode;
    final destination = checkingCurrent ? _currentEmail : _newEmail;
    return [
      Text(
        checkingCurrent
            ? 'First, enter the code sent to your current email.'
            : 'Now enter the code sent to your new email.',
      ),
      const SizedBox(height: 8),
      Text(destination, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(emailOtpLength),
        ],
        onSubmitted: (_) {
          if (!_loading) _verifyCode();
        },
        decoration: InputDecoration(
          labelText: '$emailOtpLength-digit code',
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _loading ? null : _verifyCode,
        child: Text(_loading ? 'Checking code...' : 'Verify code'),
      ),
      TextButton(
        onPressed: _loading || _remaining > 0 ? null : _resend,
        child: Text(
          _remaining > 0 ? 'Resend codes in ${_remaining}s' : 'Resend codes',
        ),
      ),
    ];
  }
}
