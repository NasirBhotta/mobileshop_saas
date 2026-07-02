import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/shop_setup_model.dart';

class SetupStepBranches extends StatefulWidget {
  final int branchCount;
  final List<BranchInputModel> branches;
  final ValueChanged<List<BranchInputModel>> onChanged;

  const SetupStepBranches({
    super.key,
    required this.branchCount,
    required this.branches,
    required this.onChanged,
  });

  @override
  State<SetupStepBranches> createState() => _SetupStepBranchesState();
}

class _SetupStepBranchesState extends State<SetupStepBranches> {
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _addressControllers;
  late List<TextEditingController> _cityControllers;

  @override
  void initState() {
    super.initState();
    // branchCount ke hisab se controllers banao
    _nameControllers = List.generate(
      widget.branchCount,
      (i) => TextEditingController(
        text: widget.branches.elementAtOrNull(i)?.name ?? '',
      ),
    );
    _addressControllers = List.generate(
      widget.branchCount,
      (i) => TextEditingController(
        text: widget.branches.elementAtOrNull(i)?.address ?? '',
      ),
    );
    _cityControllers = List.generate(
      widget.branchCount,
      (i) => TextEditingController(
        text: widget.branches.elementAtOrNull(i)?.city ?? '',
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [
      ..._nameControllers,
      ..._addressControllers,
      ..._cityControllers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _notifyParent() {
    final updated = List.generate(widget.branchCount, (i) {
      return BranchInputModel(
        name: _nameControllers[i].text.trim(),
        address: _addressControllers[i].text.trim(),
        city: _cityControllers[i].text.trim(),
      );
    });
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(widget.branchCount, (i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branch number header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Branch ${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Branch Name
              _BranchField(
                controller: _nameControllers[i],
                label: AppStrings.fieldBranchName,
                hint: i == 0 ? 'Main Branch' : 'Branch ${i + 1}',
                onChanged: (_) => _notifyParent(),
              ),
              const SizedBox(height: 10),

              // City
              _BranchField(
                controller: _cityControllers[i],
                label: AppStrings.fieldCity,
                hint: AppStrings.hintCity,
                onChanged: (_) => _notifyParent(),
              ),
              const SizedBox(height: 10),

              // Address
              _BranchField(
                controller: _addressControllers[i],
                label: AppStrings.fieldAddress,
                hint: AppStrings.hintAddress,
                onChanged: (_) => _notifyParent(),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _BranchField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  const _BranchField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
