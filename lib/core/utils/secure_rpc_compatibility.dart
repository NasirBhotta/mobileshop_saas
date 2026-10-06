import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns true only for PostgREST's explicit missing-function schema-cache
/// response. Other PGRST202 errors must not activate legacy direct-write paths.
bool isMissingSecureRpc(
  PostgrestException error,
  String functionName, {
  required String argumentName,
}) {
  if (error.code != 'PGRST202') return false;

  final message = error.message.toLowerCase();
  final expectedName = functionName.toLowerCase();
  final expectedArgument = argumentName.toLowerCase();
  return message.contains(expectedName) &&
      RegExp(
        '\\b${RegExp.escape(expectedName)}\\s*\\(\\s*${RegExp.escape(expectedArgument)}\\b',
      ).hasMatch(message) &&
      message.contains('function') &&
      message.contains('schema cache') &&
      (message.contains('could not find') ||
          message.contains('not found') ||
          message.contains('does not exist'));
}
