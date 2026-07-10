import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/settings/data/repositories/account_settings_repository.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/account_settings_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(accountSettingsProvider);
    final controllerState = ref.watch(accountSettingsControllerProvider);

    return settingsAsync.when(
      loading: () {
        return const Padding(
          padding: EdgeInsets.only(right: 12),
          child: CircleAvatar(
            radius: 17,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      error: (_, _) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            tooltip: 'Account',
            onPressed: () => context.go('/settings'),
            icon: const CircleAvatar(
              radius: 17,
              child: Icon(Icons.person_rounded, size: 18),
            ),
          ),
        );
      },
      data: (settings) {
        final currentBranch = _currentBranchName(settings);
        final avatar = _AccountAvatar(initial: _initial(settings.fullName));

        if (!Responsive.isDesktop(context)) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'Account',
              onPressed:
                  () => _showMobileAccountSheet(
                    context,
                    ref,
                    settings: settings,
                    currentBranch: currentBranch,
                    controllerState: controllerState,
                  ),
              icon: avatar,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) async {
              await _handleMenuAction(context, ref, value);
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem<String>(
                  enabled: false,
                  child: _AccountHeader(
                    fullName: settings.fullName,
                    email: settings.email,
                    role: settings.role,
                    shopName: settings.shopName,
                    branchName: currentBranch,
                    planLabel: settings.planLabel,
                    statusLabel: settings.statusLabel,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: _MenuRow(
                    icon: Icons.person_outline_rounded,
                    title: 'My Profile',
                    subtitle: 'Profile, shop and branch settings',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'switch_branch',
                  enabled: settings.branches.length > 1,
                  child: _MenuRow(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'Switch Branch',
                    subtitle:
                        settings.branches.length > 1
                            ? 'Change active branch'
                            : 'Only one branch available',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'sync',
                  enabled: !controllerState.isLoading,
                  child: _MenuRow(
                    icon: Icons.sync_rounded,
                    title:
                        controllerState.isLoading ? 'Syncing...' : 'Sync Now',
                    subtitle: 'Upload offline changes',
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'reports',
                  child: _MenuRow(
                    icon:
                        settings.canUseAdvancedReports
                            ? Icons.analytics_outlined
                            : Icons.lock_outline,
                    title: 'Business Reports',
                    subtitle:
                        settings.canUseAdvancedReports
                            ? 'Open analytics dashboard'
                            : 'Advanced reports locked',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'plan',
                  child: _MenuRow(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Plan & Billing',
                    subtitle: '${settings.planLabel} plan',
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: _MenuRow(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    subtitle: 'Sign out from this device',
                    danger: true,
                  ),
                ),
              ];
            },
            child: avatar,
          ),
        );
      },
    );
  }

  String _currentBranchName(AccountSettingsData settings) {
    for (final branch in settings.branches) {
      if (branch.id == settings.selectedBranchId) {
        return branch.name.isEmpty ? 'Current Branch' : branch.name;
      }
    }

    if (settings.branches.isNotEmpty) {
      final first = settings.branches.first;
      return first.name.isEmpty ? 'Current Branch' : first.name;
    }

    return 'No branch';
  }

  String _initial(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return '?';

    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _showMobileAccountSheet(
    BuildContext context,
    WidgetRef ref, {
    required AccountSettingsData settings,
    required String currentBranch,
    required AsyncValue<void> controllerState,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _MobileAccountSheet(
          settings: settings,
          currentBranch: currentBranch,
          controllerState: controllerState,
          onSelected: (value) async {
            Navigator.of(sheetContext).pop();
            await _handleMenuAction(context, ref, value);
          },
        );
      },
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    switch (value) {
      case 'settings':
      case 'plan':
        context.go('/settings');
        break;

      case 'switch_branch':
        context.go('/select-branch');
        break;

      case 'sync':
        final ok =
            await ref.read(accountSettingsControllerProvider.notifier).sync();

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Sync completed' : 'Sync failed')),
        );
        break;

      case 'reports':
        context.go('/reports');
        break;

      case 'logout':
        await _confirmLogout(context);
        break;
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout?'),
          content: const Text(
            'Are you sure you want to logout from this device?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await Supabase.instance.client.auth.signOut();

    if (!context.mounted) return;

    context.go('/login');
  }
}

class _AccountAvatar extends StatelessWidget {
  final String initial;

  const _AccountAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primary.withValues(alpha: 0.10),
      foregroundColor: AppColors.primary,
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _MobileAccountSheet extends StatelessWidget {
  final AccountSettingsData settings;
  final String currentBranch;
  final AsyncValue<void> controllerState;
  final ValueChanged<String> onSelected;

  const _MobileAccountSheet({
    required this.settings,
    required this.currentBranch,
    required this.controllerState,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AccountHeader(
                fullName: settings.fullName,
                email: settings.email,
                role: settings.role,
                shopName: settings.shopName,
                branchName: currentBranch,
                planLabel: settings.planLabel,
                statusLabel: settings.statusLabel,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              _MobileMenuTile(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                subtitle: 'Profile, shop and branch settings',
                onTap: () => onSelected('settings'),
              ),
              _MobileMenuTile(
                icon: Icons.store_mall_directory_outlined,
                title: 'Switch Branch',
                subtitle:
                    settings.branches.length > 1
                        ? 'Change active branch'
                        : 'Only one branch available',
                enabled: settings.branches.length > 1,
                onTap: () => onSelected('switch_branch'),
              ),
              _MobileMenuTile(
                icon: Icons.sync_rounded,
                title: controllerState.isLoading ? 'Syncing...' : 'Sync Now',
                subtitle: 'Upload offline changes',
                enabled: !controllerState.isLoading,
                onTap: () => onSelected('sync'),
              ),
              const Divider(height: 1),
              _MobileMenuTile(
                icon:
                    settings.canUseAdvancedReports
                        ? Icons.analytics_outlined
                        : Icons.lock_outline,
                title: 'Business Reports',
                subtitle:
                    settings.canUseAdvancedReports
                        ? 'Open analytics dashboard'
                        : 'Advanced reports locked',
                onTap: () => onSelected('reports'),
              ),
              _MobileMenuTile(
                icon: Icons.workspace_premium_outlined,
                title: 'Plan & Billing',
                subtitle: '${settings.planLabel} plan',
                onTap: () => onSelected('plan'),
              ),
              const Divider(height: 1),
              _MobileMenuTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                subtitle: 'Sign out from this device',
                danger: true,
                onTap: () => onSelected('logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  const _MobileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        !enabled
            ? AppColors.textSecondary
            : danger
            ? AppColors.error
            : AppColors.textPrimary;

    return ListTile(
      enabled: enabled,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: enabled ? onTap : null,
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final String fullName;
  final String email;
  final String role;
  final String shopName;
  final String branchName;
  final String planLabel;
  final String statusLabel;

  const _AccountHeader({
    required this.fullName,
    required this.email,
    required this.role,
    required this.shopName,
    required this.branchName,
    required this.planLabel,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = fullName.trim().isEmpty ? 'User' : fullName.trim();

    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                foregroundColor: AppColors.primary,
                child: Text(
                  displayName.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SmallChip(
                icon: Icons.verified_user_rounded,
                label: role.isEmpty ? 'Role not set' : role,
              ),
              _SmallChip(
                icon: Icons.workspace_premium_rounded,
                label: planLabel,
              ),
              _SmallChip(icon: Icons.verified_rounded, label: statusLabel),
            ],
          ),
          const SizedBox(height: 10),
          _HeaderInfoRow(
            icon: Icons.storefront_rounded,
            text: shopName.trim().isEmpty ? 'Shop not set' : shopName,
          ),
          const SizedBox(height: 5),
          _HeaderInfoRow(icon: Icons.account_tree_rounded, text: branchName),
        ],
      ),
    );
  }
}

class _HeaderInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _SmallChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 14),
      label: Text(label),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: danger ? AppColors.error : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
