import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:para_v3/module/appbar.dart';
import 'package:para_v3/services/auth_service.dart';

class ProfilePageVerifyOtp extends StatefulWidget {
  const ProfilePageVerifyOtp({
    super.key,
    required this.email,
    required this.purpose,
    required this.title,
    required this.description,
    this.onVerified,
    this.authService,
  });

  final String email;
  final EmailOtpPurpose purpose;
  final String title;
  final String description;
  final Future<void> Function()? onVerified;
  final AuthService? authService;

  @override
  State<ProfilePageVerifyOtp> createState() => _ProfilePageVerifyOtpState();
}

class _ProfilePageVerifyOtpState extends State<ProfilePageVerifyOtp> {
  static const _cooldownSeconds = 60;
  final _code = TextEditingController();
  Timer? _timer;
  int _remaining = _cooldownSeconds;
  bool _loading = false;

  AuthService get _auth => widget.authService ?? SupabaseAuthService.instance;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<void> _verify() async {
    if (_code.text.trim().length != emailOtpLength) {
      _show('Enter the $emailOtpLength-digit code from your email.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.verifyEmailOtp(
        email: widget.email,
        token: _code.text,
        purpose: widget.purpose,
      );
      if (!mounted) return;
      if (widget.onVerified != null) {
        await widget.onVerified!();
      } else if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
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
      switch (widget.purpose) {
        case EmailOtpPurpose.signup:
          await _auth.resendSignup(widget.email);
          break;
        case EmailOtpPurpose.recovery:
          await _auth.requestPasswordReset(widget.email);
          break;
        case EmailOtpPurpose.emailChange:
          await _auth.resendEmailChange(widget.email);
          break;
      }
      if (!mounted) return;
      _code.clear();
      _startCooldown();
      _show('A new code was sent.');
    } catch (error) {
      _show(authErrorMessage(error, fallback: 'Unable to resend the code.'));
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
    appBar: ParaAppBar(title: widget.title),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.description),
        const SizedBox(height: 8),
        Text(widget.email, style: const TextStyle(fontWeight: FontWeight.bold)),
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
            if (!_loading) _verify();
          },
          decoration: InputDecoration(
            labelText: '$emailOtpLength-digit code',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: Text(_loading ? 'Checking code...' : 'Verify code'),
        ),
        TextButton(
          onPressed: _loading || _remaining > 0 ? null : _resend,
          child: Text(
            _remaining > 0 ? 'Resend code in ${_remaining}s' : 'Resend code',
          ),
        ),
      ],
    ),
  );
}
