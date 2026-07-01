import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../providers/shop_setup_provider.dart';
import '../widgets/setup_step_basics.dart';
import '../widgets/setup_step_business.dart';
import '../widgets/setup_step_confirm.dart';

class ShopSetupScreen extends ConsumerStatefulWidget {
  const ShopSetupScreen({super.key});

  @override
  ConsumerState<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends ConsumerState<ShopSetupScreen> {
  final _basicsFormKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();

  static const _totalSteps = 3;

  @override
  void dispose() {
    _shopNameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _goNext() {
    final currentStep = ref.read(setupStepProvider);

    // Step 1 validation
    if (currentStep == 0) {
      if (!_basicsFormKey.currentState!.validate()) return;
      ref
          .read(shopSetupDataProvider.notifier)
          .updateBasics(
            shopName: _shopNameController.text.trim(),
            city: _cityController.text.trim(),
            address: _addressController.text.trim(),
          );
    }

    // Step 2 validation
    if (currentStep == 1) {
      final data = ref.read(shopSetupDataProvider);
      if (data.businessType.isEmpty) return;
    }

    if (currentStep < _totalSteps - 1) {
      ref.read(setupStepProvider.notifier).state = currentStep + 1;
    } else {
      _handleFinish();
    }
  }

  void _goBack() {
    final currentStep = ref.read(setupStepProvider);
    if (currentStep > 0) {
      ref.read(setupStepProvider.notifier).state = currentStep - 1;
    }
  }

  Future<void> _handleFinish() async {
    final success =
        await ref.read(setupSubmitControllerProvider.notifier).submitSetup();
    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = ref.watch(setupStepProvider);
    final setupData = ref.watch(shopSetupDataProvider);
    final submitState = ref.watch(setupSubmitControllerProvider);
    final isSubmitting = submitState.isLoading;
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 32 : 24,
                vertical: isDesktop ? 32 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Progress Indicator ──
                  Row(
                    children: List.generate(_totalSteps, (index) {
                      final isActive = index <= currentStep;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index < _totalSteps - 1 ? 8 : 0,
                          ),
                          height: 6,
                          decoration: BoxDecoration(
                            color:
                                isActive ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // ── Step Title ──
                  Text(
                    _stepTitle(currentStep),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepSubtitle(currentStep),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Step Content ──
                  Expanded(
                    child: SingleChildScrollView(
                      child: IndexedStack(
                        index: currentStep,
                        children: [
                          SetupStepBasics(
                            formKey: _basicsFormKey,
                            shopNameController: _shopNameController,
                            cityController: _cityController,
                            addressController: _addressController,
                          ),
                          SetupStepBusiness(
                            selectedType: setupData.businessType,
                            branchCount: setupData.branchCount,
                            onTypeChanged: (type) {
                              ref
                                  .read(shopSetupDataProvider.notifier)
                                  .updateBusinessDetails(
                                    businessType: type,
                                    branchCount: setupData.branchCount,
                                  );
                            },
                            onBranchCountChanged: (count) {
                              ref
                                  .read(shopSetupDataProvider.notifier)
                                  .updateBusinessDetails(
                                    businessType: setupData.businessType,
                                    branchCount: count,
                                  );
                            },
                          ),
                          SetupStepConfirm(data: setupData),
                        ],
                      ),
                    ),
                  ),

                  // ── Navigation Buttons ──
                  Row(
                    children: [
                      if (currentStep > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting ? null : _goBack,
                            child: Text(AppStrings.setupBack),
                          ),
                        ),
                      if (currentStep > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: currentStep > 0 ? 1 : 2,
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : _goNext,
                          child:
                              isSubmitting
                                  ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Text(
                                    currentStep == _totalSteps - 1
                                        ? AppStrings.setupFinish
                                        : AppStrings.setupNext,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0:
        return AppStrings.setupStep1Title;
      case 1:
        return AppStrings.setupStep2Title;
      default:
        return AppStrings.setupStep3Title;
    }
  }

  String _stepSubtitle(int step) {
    switch (step) {
      case 0:
        return AppStrings.setupStep1Subtitle;
      case 1:
        return AppStrings.setupStep2Subtitle;
      default:
        return AppStrings.setupStep3Subtitle;
    }
  }
}
