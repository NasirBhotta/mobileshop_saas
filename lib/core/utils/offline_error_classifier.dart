import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_error_classifier_stub.dart'
    if (dart.library.io) 'offline_error_classifier_io.dart'
    as platform;

enum OfflineErrorDisposition { retryable, terminal }

class OfflineErrorClassifier {
  const OfflineErrorClassifier._();

  static OfflineErrorDisposition classify(Object error) {
    if (error is PostgrestException || error is AuthException) {
      return OfflineErrorDisposition.terminal;
    }
    if (error is TimeoutException || platform.isConnectionFailure(error)) {
      return OfflineErrorDisposition.retryable;
    }

    final type = error.runtimeType.toString().toLowerCase();
    final message = error.toString().toLowerCase();
    if (type.contains('clientexception') &&
        _containsConnectionFailure(message)) {
      return OfflineErrorDisposition.retryable;
    }
    return OfflineErrorDisposition.terminal;
  }

  static bool isRetryable(Object error) =>
      classify(error) == OfflineErrorDisposition.retryable;

  static void rethrowIfTerminal(Object error) {
    if (!isRetryable(error)) throw error;
  }

  static bool _containsConnectionFailure(String message) {
    return message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('connection closed') ||
        message.contains('network is unreachable') ||
        message.contains('no route to host') ||
        message.contains('xmlhttprequest error') ||
        message.contains('network request failed') ||
        message.contains('failed to fetch');
  }
}
