import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('timeout is retryable', () {
    expect(
      OfflineErrorClassifier.classify(TimeoutException('slow network')),
      OfflineErrorDisposition.retryable,
    );
  });

  test('socket and DNS failures are retryable', () {
    expect(
      OfflineErrorClassifier.classify(
        const SocketException('Failed host lookup'),
      ),
      OfflineErrorDisposition.retryable,
    );
  });

  test('permission error is terminal', () {
    expect(
      OfflineErrorClassifier.classify(
        const PostgrestException(message: 'permission denied', code: '42501'),
      ),
      OfflineErrorDisposition.terminal,
    );
  });

  test('constraint error is terminal', () {
    expect(
      OfflineErrorClassifier.classify(
        const PostgrestException(message: 'foreign key', code: '23503'),
      ),
      OfflineErrorDisposition.terminal,
    );
  });

  test('PGRST and RPC business errors are terminal', () {
    expect(
      OfflineErrorClassifier.classify(
        const PostgrestException(message: 'business rule', code: 'PGRST202'),
      ),
      OfflineErrorDisposition.terminal,
    );
  });

  test('authentication error is terminal', () {
    expect(
      OfflineErrorClassifier.classify(const AuthException('expired session')),
      OfflineErrorDisposition.terminal,
    );
  });

  test('unknown errors are terminal by default', () {
    expect(
      OfflineErrorClassifier.classify(StateError('bad local state')),
      OfflineErrorDisposition.terminal,
    );
  });
}
