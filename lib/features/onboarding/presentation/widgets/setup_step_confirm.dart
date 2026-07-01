import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/shop_setup_model.dart';

class SetupStepConfirm extends StatelessWidget {
  final ShopSetupModel data;

  const SetupStepConfirm({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConfirmRow(label: AppStrings.confirmShopName, value: data.shopName),
        _ConfirmRow(label: AppStrings.confirmCity, value: data.city),
        _ConfirmRow(label: AppStrings.confirmAddress, value: data.address),
        _ConfirmRow(
          label: AppStrings.confirmBusinessType,
          value: data.businessType,
        ),
        _ConfirmRow(
          label: AppStrings.confirmBranches,
          value: data.branchCount.toString(),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
