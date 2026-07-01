import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';

class SetupStatusMessage extends StatelessWidget {
  final Object error;

  const SetupStatusMessage({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              friendlySetupError(error),
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String friendlySetupError(Object error) {
  final rawMessage =
      error is PostgrestException ? error.message : error.toString();
  final message = rawMessage.toLowerCase();

  if (message.contains('tenants')) {
    return 'Tenants table insert block ho raha hai. INSERT policy, required columns, aur RLS check karein.';
  }

  if (message.contains('users')) {
    return 'Users table update nahi ho saki. tenant_id column aur RLS policy check karein.';
  }

  if (message.contains('row-level security') || message.contains('rls')) {
    return 'Supabase RLS policy setup ko block kar rahi hai.';
  }

  if (message.contains('permission denied') ||
      message.contains('not allowed')) {
    return 'Database permission issue hai. Insert/update policy check karein.';
  }

  if (message.contains('not logged in')) {
    return 'User login nahi hai. Dobara login karke setup complete karein.';
  }

  if (message.contains('business type')) {
    return 'Business type select karein.';
  }

  if (message.contains('network') || message.contains('socket')) {
    return 'Network issue aa raha hai. Connection check karke dobara try karein.';
  }

  return rawMessage.isEmpty
      ? 'Setup complete nahi ho saka. Dobara try karein.'
      : rawMessage;
}
