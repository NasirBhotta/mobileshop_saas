import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../widgets/auth_layout.dart';

class EmailVerificationPendingScreen extends StatelessWidget {
  final String email;

  const EmailVerificationPendingScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => context.go('/signup'),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimary,
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Verify your email',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            email.isEmpty
                ? 'Hum ne verification link aap ke email par bhej diya hai.'
                : 'Hum ne verification link $email par bhej diya hai.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Email confirm karne ke baad login screen par wapas aa kar apna account access karein.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Go to login'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/signup'),
              child: const Text('Back to signup'),
            ),
          ),
        ],
      ),
    );
  }
}
