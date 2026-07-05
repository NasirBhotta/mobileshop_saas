// shared/widgets/search_bar_field.dart
import 'package:flutter/material.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';

class SearchBarField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const SearchBarField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onClear,
  });

  @override
  State<SearchBarField> createState() => _SearchBarFieldState();
}

class _SearchBarFieldState extends State<SearchBarField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textHint,
          size: 20,
        ),
        suffixIcon:
            _ctrl.text.isNotEmpty
                ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textHint,
                  ),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onChanged('');
                    widget.onClear?.call();
                  },
                )
                : null,
        // Compact styling
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
