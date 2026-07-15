import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';
import 'package:mobileshop_saas/features/settings/data/repositories/account_settings_repository.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/account_settings_provider.dart';

import '../providers/role_management_provider.dart';
import '../widgets/roles_permissions_section.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAccess = ref.watch(roleManagementAccessProvider);
    final canManageRoles = rolesAccess.when(
      data: (result) => result.isAllowed,
      loading: () => false,
      error: (_, _) => false,
    );
    final settingsAsync = ref.watch(accountSettingsProvider);
    final controllerState = ref.watch(accountSettingsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, _) => _SettingsErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(accountSettingsProvider),
              ),
          data:
              (settings) => RefreshIndicator(
                onRefresh: () async {
                  await ref
                      .read(accountSettingsControllerProvider.notifier)
                      .sync();
                  ref.invalidate(roleManagementProvider);
                },
                child: _SettingsContent(
                  settings: settings,
                  saving: controllerState.isLoading,
                  canManageRoles: canManageRoles,
                ),
              ),
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  final AccountSettingsData settings;
  final bool saving;
  final bool canManageRoles;

  const _SettingsContent({
    required this.settings,
    required this.saving,
    required this.canManageRoles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
        final header = _SettingsHeader(
          title: isWide ? 'Settings' : 'Account & Settings',
          saving: saving,
          onSync:
              saving
                  ? null
                  : () {
                    ref.read(accountSettingsControllerProvider.notifier).sync();
                  },
        );
        final profileAndShop = Column(
          children: [
            _ProfileSection(settings: settings, saving: saving),
            const SizedBox(height: 12),
            _ShopSection(settings: settings, saving: saving),
            const SizedBox(height: 12),
            _PlanBillingSection(settings: settings),
            const SizedBox(height: 12),
            _DataSyncSection(settings: settings, saving: saving),
          ],
        );
        final branches = _BranchesSection(settings: settings, saving: saving);
        final roles =
            canManageRoles
                ? const RolesPermissionsSection()
                : const SizedBox.shrink();

        if (isWide) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              header,
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: profileAndShop),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        branches,
                        if (canManageRoles) const SizedBox(height: 12),
                        roles,
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            header,
            const SizedBox(height: 12),
            profileAndShop,
            const SizedBox(height: 12),
            branches,
            if (canManageRoles) const SizedBox(height: 12),
            roles,
          ],
        );
      },
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String title;
  final bool saving;
  final VoidCallback? onSync;

  const _SettingsHeader({
    required this.title,
    required this.saving,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sync',
          onPressed: onSync,
          icon:
              saving
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.sync_rounded),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatefulWidget {
  final AccountSettingsData settings;
  final bool saving;

  const _ProfileSection({required this.settings, required this.saving});

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.settings.fullName);
    _phoneController = TextEditingController(text: widget.settings.phone);
  }

  @override
  void didUpdateWidget(covariant _ProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.fullName != widget.settings.fullName) {
      _nameController.text = widget.settings.fullName;
    }
    if (oldWidget.settings.phone != widget.settings.phone) {
      _phoneController.text = widget.settings.phone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return _SettingsCard(
          title: 'My Profile',
          subtitle: 'Owner/user details',
          icon: Icons.person_rounded,
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                enabled: !widget.saving,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: widget.settings.email,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Login email',
                  helperText: 'Auth email app se change nahi hoti.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                enabled: !widget.saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.verified_user_rounded, size: 16),
                  label: Text(
                    widget.settings.role.isEmpty
                        ? 'Role not set'
                        : widget.settings.role,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      widget.saving
                          ? null
                          : () async {
                            final ok = await ref
                                .read(
                                  accountSettingsControllerProvider.notifier,
                                )
                                .updateProfile(
                                  fullName: _nameController.text,
                                  phone: _phoneController.text,
                                );
                            if (!context.mounted) return;
                            _message(
                              context,
                              ok ? 'Profile updated' : 'Profile update failed',
                            );
                          },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShopSection extends StatefulWidget {
  final AccountSettingsData settings;
  final bool saving;

  const _ShopSection({required this.settings, required this.saving});

  @override
  State<_ShopSection> createState() => _ShopSectionState();
}

class _ShopSectionState extends State<_ShopSection> {
  late final TextEditingController _shopController;
  late final TextEditingController _businessController;

  @override
  void initState() {
    super.initState();
    _shopController = TextEditingController(text: widget.settings.shopName);
    _businessController = TextEditingController(
      text: widget.settings.businessType,
    );
  }

  @override
  void didUpdateWidget(covariant _ShopSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.shopName != widget.settings.shopName) {
      _shopController.text = widget.settings.shopName;
    }
    if (oldWidget.settings.businessType != widget.settings.businessType) {
      _businessController.text = widget.settings.businessType;
    }
  }

  @override
  void dispose() {
    _shopController.dispose();
    _businessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return _SettingsCard(
          title: 'Shop Profile',
          subtitle: '${widget.settings.branchCount} branch setup',
          icon: Icons.storefront_rounded,
          child: Column(
            children: [
              TextField(
                controller: _shopController,
                enabled: !widget.saving,
                decoration: const InputDecoration(labelText: 'Shop name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _businessController,
                enabled: !widget.saving,
                decoration: const InputDecoration(labelText: 'Business type'),
              ),

              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.workspace_premium_rounded,
                      size: 16,
                    ),
                    label: Text('Plan: ${widget.settings.planLabel}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.verified_rounded, size: 16),
                    label: Text('Status: ${widget.settings.statusLabel}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      widget.saving
                          ? null
                          : () async {
                            final ok = await ref
                                .read(
                                  accountSettingsControllerProvider.notifier,
                                )
                                .updateShop(
                                  shopName: _shopController.text,
                                  businessType: _businessController.text,
                                );
                            if (!context.mounted) return;
                            _message(
                              context,
                              ok ? 'Shop updated' : 'Shop update failed',
                            );
                          },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Shop'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlanBillingSection extends StatelessWidget {
  final AccountSettingsData settings;

  const _PlanBillingSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final isPaid = settings.canExportReports;

    return _SettingsCard(
      title: 'Plan & Billing',
      subtitle: 'Current plan and locked features',
      icon: Icons.workspace_premium_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlanHeader(settings: settings),
          const SizedBox(height: 12),
          _FeatureRow(
            title: 'CSV / PDF Report Export',
            subtitle: 'Business and Enterprise only',
            enabled: settings.canExportReports,
          ),
          _FeatureRow(
            title: 'Scheduled Reports',
            subtitle: 'Daily, weekly, monthly email reports',
            enabled: settings.canScheduleReports,
          ),
          _FeatureRow(
            title: 'All Branches Analytics',
            subtitle: 'Combined analytics across branches',
            enabled: settings.canUseMultiBranchAnalytics,
          ),
          _FeatureRow(
            title: 'Advanced Business Reports',
            subtitle: 'P&L, cash flow, inventory, customer credit',
            enabled: settings.canUseAdvancedReports,
          ),
          const SizedBox(height: 12),
          if (!isPaid)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _message(
                    context,
                    'Upgrade flow baad mein billing module ke sath connect hoga.',
                  );
                },
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Upgrade to Business'),
              ),
            )
          else
            const _InfoBox(
              icon: Icons.check_circle_outline_rounded,
              text:
                  'Your plan can access export, scheduled reports and advanced analytics.',
            ),
        ],
      ),
    );
  }
}

class _DataSyncSection extends ConsumerWidget {
  final AccountSettingsData settings;
  final bool saving;

  const _DataSyncSection({required this.settings, required this.saving});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsCard(
      title: 'Data & Sync',
      subtitle: 'Offline changes and cloud synchronization',
      icon: Icons.sync_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoBox(
            icon: Icons.cloud_done_outlined,
            text:
                'App offline-first hai. Internet weak ho to changes local save hoti hain aur baad mein sync hoti hain.',
          ),
          const SizedBox(height: 12),
          _SyncInfoRow(
            title: 'Profile, shop and branch changes',
            subtitle: 'Offline queue supported',
            icon: Icons.person_rounded,
          ),
          _SyncInfoRow(
            title: 'Inventory, sales, expenses and reports',
            subtitle: 'Module sync providers ke through handle hota hai',
            icon: Icons.storage_rounded,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  saving
                      ? null
                      : () async {
                        final ok =
                            await ref
                                .read(
                                  accountSettingsControllerProvider.notifier,
                                )
                                .sync();

                        if (!context.mounted) return;

                        _message(
                          context,
                          ok ? 'Sync completed' : 'Sync failed',
                        );
                      },
              icon:
                  saving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.sync_rounded),
              label: Text(saving ? 'Syncing...' : 'Sync Now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncInfoRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SyncInfoRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.08),
            foregroundColor: AppColors.primary,
            child: Icon(icon, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  final AccountSettingsData settings;

  const _PlanHeader({required this.settings});

  @override
  Widget build(BuildContext context) {
    final color =
        settings.status.toLowerCase() == 'active'
            ? AppColors.primary
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: const Icon(Icons.workspace_premium_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.planLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Status: ${settings.statusLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;

  const _FeatureRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final icon = enabled ? Icons.check_circle_rounded : Icons.lock_outline;
    final color = enabled ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            enabled ? 'Enabled' : 'Locked',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BranchesSection extends ConsumerWidget {
  final AccountSettingsData settings;
  final bool saving;

  const _BranchesSection({required this.settings, required this.saving});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsCard(
      title: 'Branches',
      subtitle: 'Names, address, city and current branch',
      icon: Icons.account_tree_rounded,
      child: Column(
        children: [
          if (settings.branches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No branch found.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final branch in settings.branches)
              _BranchTile(
                branch: branch,
                selected: branch.id == settings.selectedBranchId,
                saving: saving,
                onSelect:
                    branch.id == null || branch.id == settings.selectedBranchId
                        ? null
                        : () async {
                          final ok = await ref
                              .read(accountSettingsControllerProvider.notifier)
                              .selectBranch(branch.id!);
                          if (!context.mounted) return;
                          _message(
                            context,
                            ok
                                ? 'Branch selected'
                                : 'Branch select nahi ho saki',
                          );
                        },
                onEdit:
                    branch.id == null
                        ? null
                        : () => _showBranchDialog(context, ref, branch),
              ),
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  final BranchInputModel branch;
  final bool selected;
  final bool saving;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;

  const _BranchTile({
    required this.branch,
    required this.selected,
    required this.saving,
    required this.onSelect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    selected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.surfaceVariant,
                foregroundColor:
                    selected ? AppColors.primary : AppColors.textSecondary,
                child: const Icon(Icons.store_rounded, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            branch.name.isEmpty
                                ? 'Unnamed branch'
                                : branch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (selected)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('Current'),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      [
                        branch.address,
                        branch.city,
                      ].where((item) => item.trim().isNotEmpty).join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit branch',
                onPressed: saving ? null : onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
          if (!selected && onSelect != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: saving ? null : onSelect,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Use this branch'),
              ),
            ),
          ],
          const Divider(height: 18),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
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
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SettingsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SettingsErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        const Icon(
          Icons.error_outline_rounded,
          size: 52,
          color: AppColors.error,
        ),
        const SizedBox(height: 12),
        Text(
          'Settings load nahi ho sake',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

Future<void> _showBranchDialog(
  BuildContext context,
  WidgetRef ref,
  BranchInputModel branch,
) async {
  final nameController = TextEditingController(text: branch.name);
  final addressController = TextEditingController(text: branch.address);
  final cityController = TextEditingController(text: branch.city);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Edit Branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Branch name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(labelText: 'City'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(accountSettingsControllerProvider.notifier)
                  .updateBranch(
                    branch: branch,
                    name: nameController.text,
                    address: addressController.text,
                    city: cityController.text,
                  );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (context.mounted) {
                _message(
                  context,
                  ok ? 'Branch updated' : 'Branch update failed',
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  addressController.dispose();
  cityController.dispose();
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
