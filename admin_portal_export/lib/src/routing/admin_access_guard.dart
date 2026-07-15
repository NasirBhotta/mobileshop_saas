import '../auth/domain/admin_access.dart';

String? adminRedirect({required AdminAccess access, required String location}) {
  final onLogin = location == '/login';
  final onDenied = location == '/access-denied';
  final onLoading = location == '/loading';

  return switch (access) {
    AdminAccess.signedOut => onLogin ? null : '/login',
    AdminAccess.accessDenied => onDenied ? null : '/access-denied',
    AdminAccess.platformAdmin => onLogin || onDenied || onLoading ? '/' : null,
  };
}
