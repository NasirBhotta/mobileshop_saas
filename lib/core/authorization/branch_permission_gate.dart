import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/widgets/account_menu_button.dart';
import '../constants/app_colors.dart';
import 'branch_permission_shadow_provider.dart';
import 'permission_locked_screen.dart';

class BranchPermissionGate extends ConsumerWidget {
  final String permissionKey;
  final String moduleName;
  final Widget child;

  const BranchPermissionGate({
    required this.permissionKey,
    required this.moduleName,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(branchAwarePermissionProvider(permissionKey));

    return access.when(
      loading:
          () => const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          ),
      error:
          (_, _) => PermissionLockedScreen(
            moduleName: moduleName,
            accountAction: const AccountMenuButton(),
          ),
      data:
          (isAllowed) =>
              isAllowed
                  ? child
                  : PermissionLockedScreen(
                    moduleName: moduleName,
                    accountAction: const AccountMenuButton(),
                  ),
    );
  }
}
