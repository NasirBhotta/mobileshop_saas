import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/widgets/logout_action.dart';
import '../../data/models/shop_setup_model.dart';
import '../../data/repositories/setup_flow_repository.dart';
import '../widgets/setup_status_message.dart';

final branchSelectionProvider = FutureProvider<List<BranchInputModel>>((
  ref,
) async {
  final repository = ref.read(setupFlowRepositoryProvider);
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('User not logged in');

  final status = await repository.loadStatus(user.id);
  final tenantId = status.profile?['tenant_id'] as String?;
  if (tenantId == null) throw Exception('Tenant setup required');

  return repository.loadBranches(tenantId);
});

class BranchSelectionScreen extends ConsumerWidget {
  const BranchSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint("BranchSelectionScreen BUILD");
    final branchesState = ref.watch(branchSelectionProvider);
    final isLoggingOut = ref.watch(authControllerProvider).isLoading;
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 720 : double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 32 : 24,
                vertical: 32,
              ),
              child: branchesState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => SetupStatusMessage(error: error),
                data:
                    (branches) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select Branch',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Choose the branch you want to open.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (branches.length >= 2) ...[
                              const SizedBox(width: 12),
                              TextButton.icon(
                                onPressed:
                                    isLoggingOut
                                        ? null
                                        : () => confirmLogout(context, ref),
                                icon:
                                    isLoggingOut
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(
                                          Icons.logout_rounded,
                                          size: 18,
                                        ),
                                label: const Text(AppStrings.logout),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: ListView.separated(
                            itemCount: branches.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final branch = branches[index];
                              return _BranchTile(
                                branch: branch,
                                onTap:
                                    () => _selectBranch(context, ref, branch),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectBranch(
    BuildContext context,
    WidgetRef ref,
    BranchInputModel branch,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    final branchId = branch.id;
    if (user == null || branchId == null) return;

    try {
      await ref
          .read(setupFlowRepositoryProvider)
          .selectBranch(userId: user.id, branchId: branchId);
      ref.invalidate(setupFlowStatusProvider);

      if (context.mounted) {
        context.go('/dashboard');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlySetupError(error))));
      }
    }
  }
}

class _BranchTile extends StatelessWidget {
  final BranchInputModel branch;
  final VoidCallback onTap;

  const _BranchTile({required this.branch, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.name.isEmpty ? 'Branch' : branch.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (branch.city.isNotEmpty || branch.address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          branch.address,
                          branch.city,
                        ].where((value) => value.isNotEmpty).join(', '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
