import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class SetupStepBusiness extends StatelessWidget {
  final String selectedType;
  final int branchCount;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int> onBranchCountChanged;

  const SetupStepBusiness({
    super.key,
    required this.selectedType,
    required this.branchCount,
    required this.onTypeChanged,
    required this.onBranchCountChanged,
  });

  static const _types = [
    AppStrings.businessTypeMobile,
    AppStrings.businessTypeElectronics,
    AppStrings.businessTypeBoth,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.fieldBusinessType,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // ── Business Type Cards ──
        ..._types.map((type) {
          final isSelected = selectedType == type;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => onTypeChanged(type),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color:
                          isSelected ? AppColors.primary : AppColors.textHint,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      type,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
        const Text(
          AppStrings.fieldBranchCount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // ── Branch Count Stepper ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed:
                    branchCount > 1
                        ? () => onBranchCountChanged(branchCount - 1)
                        : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: AppColors.primary,
              ),
              Text(
                branchCount.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () => onBranchCountChanged(branchCount + 1),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
