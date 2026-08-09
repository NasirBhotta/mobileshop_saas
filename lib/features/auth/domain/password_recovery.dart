import 'package:flutter/foundation.dart';

const nativePasswordRecoveryCallback =
    'io.supabase.mobileshop://login-callback/';

String passwordRecoveryRedirectUrl({Uri? browserUri}) {
  if (!kIsWeb) return nativePasswordRecoveryCallback;

  final current = browserUri ?? Uri.base;
  return current
      .replace(path: '/reset-password', query: null, fragment: null)
      .toString();
}

String passwordRecoveryErrorMessage(Object error) {
  final value = error.toString().toLowerCase();
  if (value.contains('network') ||
      value.contains('socket') ||
      value.contains('timeout')) {
    return 'Internet connection check karke dobara try karein.';
  }
  if (value.contains('rate') || value.contains('too many')) {
    return 'Bohat zyada attempts ho gaye hain. Kuch dair baad try karein.';
  }
  return 'Reset link send nahi ho saka. Thori dair baad dobara try karein.';
}

String maskRecoveryEmail(String email) {
  final parts = email.trim().split('@');
  if (parts.length != 2 || parts.first.isEmpty) return email.trim();
  final name = parts.first;
  final visible =
      name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
  return '$visible${'*' * (name.length - visible.length)}@${parts.last}';
}
