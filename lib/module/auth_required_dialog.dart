import 'package:flutter/material.dart';
import 'package:para_v3/module/universal_alert_dialog.dart';
import 'package:para_v3/pages/profile_page_sign_in.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';

class AuthRequiredDialog {
  const AuthRequiredDialog._();

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String content,
  }) {
    return UniversalAlertDialog.show(
      context: context,
      title: title,
      content: content,
      secondaryButtonText: 'Sign in',
      onSecondaryPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfilePageSignIn()),
      ),
      primaryButtonText: 'Create account',
      onPrimaryPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfilePageSignUp()),
      ),
    );
  }
}
