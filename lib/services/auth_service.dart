import 'package:supabase_flutter/supabase_flutter.dart';

enum EmailOtpPurpose { signup, recovery, emailChange }

enum SignUpOutcome { signedIn, verificationRequired, possiblyExisting }

const emailOtpLength = 6;
const passwordRequirementsMessage =
    'Use at least 6 characters with an uppercase letter, lowercase letter, '
    'number, and special character.';

abstract class AuthService {
  String? get currentEmail;

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  });
  Future<void> signIn({required String email, required String password});
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
    required EmailOtpPurpose purpose,
  });
  Future<void> resendSignup(String email);
  Future<void> requestPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> beginEmailChange({
    required String currentEmail,
    required String newEmail,
    required String password,
  });
  Future<void> resendEmailChange(String newEmail);
  Future<void> deleteAccount(String password);
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService._();

  static final instance = SupabaseAuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: normalizeEmail(email),
      password: password,
    );
    if (response.session != null) return SignUpOutcome.signedIn;

    if (response.user?.identities?.isEmpty == true) {
      return SignUpOutcome.possiblyExisting;
    }
    return SignUpOutcome.verificationRequired;
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: normalizeEmail(email),
      password: password,
    );
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
    required EmailOtpPurpose purpose,
  }) async {
    await _client.auth.verifyOTP(
      email: normalizeEmail(email),
      token: token.trim(),
      type: switch (purpose) {
        EmailOtpPurpose.signup => OtpType.signup,
        EmailOtpPurpose.recovery => OtpType.recovery,
        EmailOtpPurpose.emailChange => OtpType.emailChange,
      },
    );
  }

  @override
  Future<void> resendSignup(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: normalizeEmail(email),
    );
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(normalizeEmail(email));

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> beginEmailChange({
    required String currentEmail,
    required String newEmail,
    required String password,
  }) async {
    await signIn(email: currentEmail, password: password);
    await _client.auth.updateUser(
      UserAttributes(email: normalizeEmail(newEmail)),
    );
  }

  @override
  Future<void> resendEmailChange(String newEmail) async {
    await _client.auth.resend(
      type: OtpType.emailChange,
      email: normalizeEmail(newEmail),
    );
  }

  @override
  Future<void> deleteAccount(String password) async {
    await _client.functions.invoke(
      'delete-account',
      body: {'password': password},
    );
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}

String normalizeEmail(String value) => value.trim().toLowerCase();

bool isValidEmail(String value) {
  final email = normalizeEmail(value);
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

bool isStrongPassword(String value) {
  return RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9\s])\S{6,}$',
  ).hasMatch(value);
}

String authErrorMessage(
  Object error, {
  String fallback = 'Something went wrong.',
}) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'The email or password is incorrect.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email before signing in.';
    }
    if (message.contains('expired') || message.contains('invalid token')) {
      return 'That code is invalid or has expired. Request a new code.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait before trying again.';
    }
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'An account with that email already exists.';
    }
    return error.message;
  }
  if (error is FunctionException) {
    if (error.status == 401) return 'Your session has expired. Sign in again.';
    if (error.status == 403) return 'The password is incorrect.';
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
  }
  return fallback;
}
