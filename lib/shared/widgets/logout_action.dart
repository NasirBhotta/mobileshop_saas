import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text(AppStrings.logoutTitle),
          content: const Text(AppStrings.logoutMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(AppStrings.logout),
            ),
          ],
        ),
  );

  if (shouldLogout != true || !context.mounted) return;

  final loggedOut = await ref.read(authControllerProvider.notifier).logout();
  if (!context.mounted) return;

  if (loggedOut) {
    context.go('/login');
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.somethingWentWrong)),
    );
  }
}
