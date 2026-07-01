import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';

class AuthStatusMessage extends StatelessWidget {
  final Object error;

  const AuthStatusMessage({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
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
              friendlyAuthError(error),
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

String friendlyAuthError(Object error) {
  final rawMessage = error is AuthException ? error.message : error.toString();
  final message = rawMessage.toLowerCase();

  if (message.contains('invalid login credentials') ||
      message.contains('invalid credentials')) {
    return 'Email ya password sahi nahi hai.';
  }

  if (message.contains('email not confirmed') ||
      message.contains('not confirmed')) {
    return 'Pehle apna email verify karein, phir login karein.';
  }

  if (message.contains('already registered') ||
      message.contains('user already') ||
      message.contains('already exists') ||
      message.contains('duplicate key')) {
    return 'Is email se account pehle se mojood hai. Login karein ya doosra email use karein.';
  }

  if (message.contains('weak password') ||
      message.contains('password should be')) {
    return 'Password strong nahi hai. Kam az kam 6 characters ka password use karein.';
  }

  if (message.contains('signup disabled') ||
      message.contains('signups not allowed')) {
    return 'Signup abhi enabled nahi hai. Supabase auth settings check karein.';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return 'Network issue aa raha hai. Internet connection check karke dobara try karein.';
  }

  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Bohat zyada attempts ho gaye hain. Ye limit aksar email nahi, device/network par hoti hai. Thori der baad dobara try karein.';
  }

  return rawMessage.isEmpty
      ? 'Kuch ghalat ho gaya. Dobara try karein.'
      : rawMessage;
}
