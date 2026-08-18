import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/pages/auth_page.dart';

void main() {
  testWidgets('auth page switches between sign in and account creation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.text('New to Para? Create an account'));
    await tester.pump();

    expect(find.text('Join Para'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
  });

  testWidgets('password update page validates matching passwords', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: UpdatePasswordPage(isRecovery: true)),
    );

    expect(find.text('Reset password'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'strong-password',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'different-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });
}
