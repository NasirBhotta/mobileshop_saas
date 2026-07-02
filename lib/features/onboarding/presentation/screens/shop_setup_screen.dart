import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/shop_setup_model.dart';
import '../../data/repositories/setup_flow_repository.dart';
import '../providers/shop_setup_provider.dart';
import '../widgets/setup_status_message.dart';
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
  final _branchFormKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchCityController = TextEditingController();
  final _branchAddressController = TextEditingController();
  bool _isRedirectingCompletedSetup = false;

  static const _totalSteps = 4;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(setupSubmitControllerProvider.notifier).loadResumeState();
    });
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _branchNameController.dispose();
    _branchCityController.dispose();
    _branchAddressController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    final currentStep = ref.read(setupStepProvider);

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

    if (currentStep == 1) {
      final data = ref.read(shopSetupDataProvider);
      if (data.businessType.isEmpty) {
        ref
            .read(setupSubmitControllerProvider.notifier)
            .setValidationError('Business type required');
        return;
      }
    }

    if (currentStep == 2) {
      await _handleBusinessSetup();
      return;
    }

    if (currentStep == 3) {
      await _handleBranchSubmit();
      return;
    }

    ref.read(setupStepProvider.notifier).state = currentStep + 1;
  }

  void _goBack() {
    final currentStep = ref.read(setupStepProvider);
    if (currentStep > 0 && currentStep < 3) {
      ref.read(setupStepProvider.notifier).state = currentStep - 1;
    }
  }

  Future<void> _handleBusinessSetup() async {
    final success =
        await ref
            .read(setupSubmitControllerProvider.notifier)
            .submitBusinessSetup();

    if (!success || !mounted) return;

    final setupData = ref.read(shopSetupDataProvider);
    final progress = ref.read(setupProgressProvider);
    if (progress.completedBranches == 0) {
      _branchNameController.text = 'Main Branch';
      _branchCityController.text = setupData.city;
      _branchAddressController.text = setupData.address;
    }
  }

  Future<void> _handleBranchSubmit() async {
    if (!_branchFormKey.currentState!.validate()) return;

    final target = await ref
        .read(setupSubmitControllerProvider.notifier)
        .submitCurrentBranch(
          BranchInputModel(
            name: _branchNameController.text.trim(),
            city: _branchCityController.text.trim(),
            address: _branchAddressController.text.trim(),
          ),
        );

    if (!mounted || target == null) return;

    if (target == SetupRouteTarget.branchSelection) {
      context.go('/select-branch');
      return;
    }

    if (target == SetupRouteTarget.dashboard) {
      context.go('/dashboard');
      return;
    }

    final progress = ref.read(setupProgressProvider);
    _branchNameController.text = 'Branch ${progress.nextBranchNumber}';
    _branchCityController.clear();
    _branchAddressController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = ref.watch(setupStepProvider);
    final setupData = ref.watch(shopSetupDataProvider);
    final setupProgress = ref.watch(setupProgressProvider);
    final submitState = ref.watch(setupSubmitControllerProvider);
    final isSubmitting = submitState.isLoading;
    final submitError = submitState.hasError ? submitState.error : null;
    final isDesktop = Responsive.isDesktop(context);

    if (currentStep == 3 && setupProgress.isComplete) {
      if (submitError != null) {
        return _CompletedSetupError(
          error: submitError,
          onRetry: isSubmitting ? null : _redirectCompletedSetup,
        );
      }

      _redirectCompletedSetup();
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                  Text(
                    _stepTitle(currentStep, setupProgress),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepSubtitle(currentStep, setupProgress),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
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
                                  .read(setupSubmitControllerProvider.notifier)
                                  .clearStatus();
                              ref
                                  .read(shopSetupDataProvider.notifier)
                                  .updateBusinessDetails(
                                    businessType: type,
                                    branchCount: setupData.branchCount,
                                  );
                            },
                            onBranchCountChanged: (count) {
                              ref
                                  .read(setupSubmitControllerProvider.notifier)
                                  .clearStatus();
                              ref
                                  .read(shopSetupDataProvider.notifier)
                                  .updateBusinessDetails(
                                    businessType: setupData.businessType,
                                    branchCount: count,
                                  );
                            },
                          ),
                          SetupStepConfirm(data: setupData),
                          _CurrentBranchStep(
                            formKey: _branchFormKey,
                            branchNumber: setupProgress.nextBranchNumber,
                            totalBranches: setupProgress.branchCount,
                            nameController: _branchNameController,
                            cityController: _branchCityController,
                            addressController: _branchAddressController,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (submitError != null)
                    SetupStatusMessage(error: submitError),
                  Row(
                    children: [
                      if (currentStep > 0 && currentStep < 3)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting ? null : _goBack,
                            child: Text(AppStrings.setupBack),
                          ),
                        ),
                      if (currentStep > 0 && currentStep < 3)
                        const SizedBox(width: 12),
                      Expanded(
                        flex: currentStep > 0 && currentStep < 3 ? 1 : 2,
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
                                    currentStep >= 2
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

  void _redirectCompletedSetup() {
    if (_isRedirectingCompletedSetup) return;
    _isRedirectingCompletedSetup = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target =
          await ref
              .read(setupSubmitControllerProvider.notifier)
              .completeSetupIfReady();

      if (!mounted || target == null) {
        _isRedirectingCompletedSetup = false;
        return;
      }

      if (target == SetupRouteTarget.branchSelection) {
        context.go('/select-branch');
      } else {
        context.go('/dashboard');
      }
    });
  }

  String _stepTitle(int step, SetupProgressState progress) {
    switch (step) {
      case 0:
        return AppStrings.setupStep1Title;
      case 1:
        return AppStrings.setupStep2Title;
      case 2:
        return AppStrings.setupStep3Title;
      default:
        return 'Branch ${progress.nextBranchNumber} Setup';
    }
  }

  String _stepSubtitle(int step, SetupProgressState progress) {
    switch (step) {
      case 0:
        return AppStrings.setupStep1Subtitle;
      case 1:
        return AppStrings.setupStep2Subtitle;
      case 2:
        return AppStrings.setupStep3Subtitle;
      default:
        return '${progress.completedBranches} of ${progress.branchCount} branches saved';
    }
  }
}

class _CompletedSetupError extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _CompletedSetupError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Setup finalize nahi ho saka',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SetupStatusMessage(error: error),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Dobara Try Karein'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentBranchStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final int branchNumber;
  final int totalBranches;
  final TextEditingController nameController;
  final TextEditingController cityController;
  final TextEditingController addressController;

  const _CurrentBranchStep({
    required this.formKey,
    required this.branchNumber,
    required this.totalBranches,
    required this.nameController,
    required this.cityController,
    required this.addressController,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              'Branch $branchNumber of $totalBranches',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: AppStrings.fieldBranchName,
              hintText:
                  branchNumber == 1 ? 'Main Branch' : 'Branch $branchNumber',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: cityController,
            decoration: const InputDecoration(
              labelText: AppStrings.fieldCity,
              hintText: AppStrings.hintCity,
            ),
            validator:
                (value) =>
                    value == null || value.trim().isEmpty
                        ? AppStrings.errorCityRequired
                        : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: addressController,
            decoration: const InputDecoration(
              labelText: AppStrings.fieldAddress,
              hintText: AppStrings.hintAddress,
            ),
            validator:
                (value) =>
                    value == null || value.trim().isEmpty
                        ? AppStrings.errorAddressRequired
                        : null,
          ),
        ],
      ),
    );
  }
}
