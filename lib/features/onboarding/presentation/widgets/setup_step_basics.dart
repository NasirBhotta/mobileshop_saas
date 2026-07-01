import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../auth/presentation/widgets/auth_text_field.dart';

class SetupStepBasics extends StatelessWidget {
  final TextEditingController shopNameController;
  final TextEditingController cityController;
  final TextEditingController addressController;
  final GlobalKey<FormState> formKey;

  const SetupStepBasics({
    super.key,
    required this.shopNameController,
    required this.cityController,
    required this.addressController,
    required this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthTextField(
            controller: shopNameController,
            label: AppStrings.fieldShopName,
            hint: AppStrings.hintShopName,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppStrings.errorShopNameRequired;
              }
              return null;
            },
          ),
          AuthTextField(
            controller: cityController,
            label: AppStrings.fieldCity,
            hint: AppStrings.hintCity,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppStrings.errorCityRequired;
              }
              return null;
            },
          ),
          AuthTextField(
            controller: addressController,
            label: AppStrings.fieldAddress,
            hint: AppStrings.hintAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppStrings.errorAddressRequired;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}
