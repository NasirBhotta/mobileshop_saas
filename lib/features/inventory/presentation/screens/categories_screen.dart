import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../providers/inventory_provider.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesState = ref.watch(categoriesProvider);
    final isMutating = ref.watch(categoryControllerProvider).isLoading;

    return LoadingOverlay(
      isLoading: isMutating,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text(AppStrings.categoriesTitle)),
        floatingActionButton: FloatingActionButton(
          onPressed: isMutating ? null : () => _showAddDialog(context, ref),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
        body: categoriesState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (categories) {
            if (categories.isEmpty) {
              return const Center(
                child: Text(
                  'Koi category nahi — pehli add karein!',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.label_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cat.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),

                      SizedBox(
                        width: 60,
                        child: TextFormField(
                          key: ValueKey(
                            'category-threshold-${cat.id}-${cat.defaultReorderThreshold}',
                          ),
                          initialValue: cat.defaultReorderThreshold.toString(),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            helperText: 'Default',
                          ),
                          onChanged: (val) async {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed >= 1) {
                              await ref
                                  .read(inventoryRepositoryProvider)
                                  .updateCategoryThreshold(
                                    categoryId: cat.id,
                                    threshold: parsed,
                                  );
                              ref.invalidate(categoriesProvider);
                              ref.invalidate(allProductsProvider);
                              ref.invalidate(productsProvider);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed:
                            isMutating
                                ? null
                                : () async {
                                  await ref
                                      .read(categoryControllerProvider.notifier)
                                      .deleteCategory(cat.id);
                                },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text(AppStrings.categoryAddNew),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: AppStrings.hintCategoryName,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (controller.text.trim().isEmpty) return;
                  await ref
                      .read(categoryControllerProvider.notifier)
                      .addCategory(controller.text.trim());
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }
}
