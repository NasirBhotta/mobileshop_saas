import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../features/dashboard/presentation/providers/dashboard_provider.dart';
import '../../../../features/inventory/presentation/providers/inventory_provider.dart';
import '../../../../features/pos/presentation/providers/pos_provider.dart';
import '../../../../shared/providers/navigation_loading_provider.dart';
import '../../data/models/shop_setup_model.dart';
import '../../data/repositories/setup_flow_repository.dart';
import '../widgets/setup_status_message.dart';

final branchSelectionProvider = FutureProvider.autoDispose
    .family<List<BranchInputModel>, String>((ref, userId) async {
      final repository = ref.read(setupFlowRepositoryProvider);
      final status = await repository.loadStatus(userId);
      final tenantId = status.profile?['tenant_id'] as String?;
      if (tenantId == null) throw Exception('Tenant setup required');

      return repository.loadBranches(tenantId);
    });

class BranchSelectionScreen extends ConsumerStatefulWidget {
  const BranchSelectionScreen({super.key});

  @override
  ConsumerState<BranchSelectionScreen> createState() =>
      _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends ConsumerState<BranchSelectionScreen> {
  String? _selectingBranchId;

  @override
  Widget build(BuildContext context) {
    debugPrint("BranchSelectionScreen BUILD");
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final branchesState =
        userId == null
            ? const AsyncValue<List<BranchInputModel>>.error(
              'User not logged in',
              StackTrace.empty,
            )
            : ref.watch(branchSelectionProvider(userId));
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
                        const Column(
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
                        const SizedBox(height: 24),
                        Expanded(
                          child: ListView.separated(
                            itemCount: branches.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final branch = branches[index];
                              final isSelecting =
                                  _selectingBranchId == branch.id;
                              return _BranchTile(
                                branch: branch,
                                isLoading: isSelecting,
                                onTap:
                                    _selectingBranchId == null
                                        ? () =>
                                            _selectBranch(context, ref, branch)
                                        : null,
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

    setState(() => _selectingBranchId = branchId);
    try {
      await ref
          .read(setupFlowRepositoryProvider)
          .selectBranch(userId: user.id, branchId: branchId);
      ref.invalidate(setupFlowStatusProvider);
      ref.invalidate(selectedBranchIdProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(allProductsProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(salesHistoryProvider);
      ref.invalidate(heldCartsProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(pendingReturnsProvider);
      ref.invalidate(approvedReturnsProvider);
      ref.invalidate(returnDraftProvider);
      ref.invalidate(returnControllerProvider);

      if (context.mounted) {
        ref.read(navigationLoadingProvider.notifier).showFor();
        context.go('/dashboard');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlySetupError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _selectingBranchId = null);
      }
    }
  }
}

class _BranchTile extends StatelessWidget {
  final BranchInputModel branch;
  final VoidCallback? onTap;
  final bool isLoading;

  const _BranchTile({
    required this.branch,
    required this.onTap,
    required this.isLoading,
  });

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
            if (isLoading)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
          ],
        ),
      ),
    );
  }
}
