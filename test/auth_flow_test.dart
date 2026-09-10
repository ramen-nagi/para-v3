import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:para_v3/pages/profile_page_sign_up.dart';
import 'package:para_v3/pages/profile_page_reset_password.dart';
import 'package:para_v3/pages/profile_page_change_email.dart';
import 'package:para_v3/pages/profile_page_verify_otp.dart';
import 'package:para_v3/services/auth_service.dart';

void main() {
  group('email helpers', () {
    test('normalizes and validates email addresses', () {
      expect(normalizeEmail('  USER@Example.COM '), 'user@example.com');
      expect(isValidEmail('person@example.com'), isTrue);
      expect(isValidEmail('not-an-email'), isFalse);
    });
  });

  group('password helpers', () {
    test('requires every password character category', () {
      expect(isStrongPassword('Secret1!'), isTrue);
      expect(isStrongPassword('secret1!'), isFalse);
      expect(isStrongPassword('SECRET1!'), isFalse);
      expect(isStrongPassword('Secret!!'), isFalse);
      expect(isStrongPassword('Secret12'), isFalse);
      expect(isStrongPassword('S1!a'), isFalse);
    });
  });

  testWidgets('signup with confirmation opens OTP screen', (tester) async {
    final auth = _FakeAuthService(
      signUpOutcome: SignUpOutcome.verificationRequired,
    );
    await tester.pumpWidget(
      MaterialApp(home: ProfilePageSignUp(authService: auth)),
    );

    await tester.enterText(find.byType(TextField).at(0), ' USER@example.com ');
    await tester.enterText(find.byType(TextField).at(1), 'Secret1!');
    await tester.enterText(find.byType(TextField).at(2), 'Secret1!');
    await tester.ensureVisible(find.text('Sign up'));
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(auth.signupEmail, 'user@example.com');
    expect(find.text('Confirm your email'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('possible duplicate signup offers account recovery actions', (
    tester,
  ) async {
    final auth = _FakeAuthService(
      signUpOutcome: SignUpOutcome.possiblyExisting,
    );
    await tester.pumpWidget(
      MaterialApp(home: ProfilePageSignUp(authService: auth)),
    );

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Secret1!');
    await tester.enterText(find.byType(TextField).at(2), 'Secret1!');
    await tester.ensureVisible(find.text('Sign up'));
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Check your account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Confirm your email'), findsNothing);
  });

  testWidgets('OTP screen rejects incomplete code', (tester) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePageVerifyOtp(
          email: 'user@example.com',
          purpose: EmailOtpPurpose.signup,
          title: 'Confirm your email',
          description: 'Enter the code sent to',
          authService: auth,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verify code'));
    await tester.pump();

    expect(
      find.text('Enter the 6-digit code from your email.'),
      findsOneWidget,
    );
    expect(auth.verifiedToken, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('OTP screen submits a six-digit code', (tester) async {
    final auth = _FakeAuthService();
    var verified = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePageVerifyOtp(
          email: 'user@example.com',
          purpose: EmailOtpPurpose.signup,
          title: 'Confirm your email',
          description: 'Enter the code sent to',
          authService: auth,
          onVerified: () async => verified = true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pump();

    expect(auth.verifiedToken, '123456');
    expect(auth.verifiedPurpose, EmailOtpPurpose.signup);
    expect(verified, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('password recovery verifies OTP before accepting a password', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: ProfilePageResetPassword(authService: auth)),
    );

    await tester.enterText(find.byType(TextField), 'USER@example.com');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();

    expect(auth.resetEmail, 'user@example.com');
    expect(find.text('Verify reset code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(auth.verifiedPurpose, EmailOtpPurpose.recovery);
    expect(find.text('Set new password'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('secure email change verifies the current inbox first', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: ProfilePageChangeEmail(authService: auth)),
    );

    await tester.enterText(find.byType(TextField).at(0), 'NEW@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
    await tester.pump();

    expect(auth.changedToEmail, 'new@example.com');
    expect(find.text('current@example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text('Verify code'));
    await tester.pump();

    expect(auth.verifiedEmails.single, 'current@example.com');
    expect(find.text('new@example.com'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({this.signUpOutcome = SignUpOutcome.signedIn});

  final SignUpOutcome signUpOutcome;
  String? signupEmail;
  String? resetEmail;
  String? changedToEmail;
  String? verifiedToken;
  EmailOtpPurpose? verifiedPurpose;
  final verifiedEmails = <String>[];

  @override
  String? get currentEmail => 'current@example.com';

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    signupEmail = email;
    return signUpOutcome;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
    required EmailOtpPurpose purpose,
  }) async {
    verifiedToken = token;
    verifiedPurpose = purpose;
    verifiedEmails.add(email);
  }

  @override
  Future<void> beginEmailChange({
    required String currentEmail,
    required String newEmail,
    required String password,
  }) async {
    changedToEmail = newEmail;
  }

  @override
  Future<void> deleteAccount(String password) async {}

  @override
  Future<void> requestPasswordReset(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> resendEmailChange(String newEmail) async {}

  @override
  Future<void> resendSignup(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> updatePassword(String password) async {}
}
