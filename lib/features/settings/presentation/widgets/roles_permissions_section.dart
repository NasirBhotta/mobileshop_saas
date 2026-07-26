import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/role_management_models.dart';
import '../../data/repositories/role_management_repository.dart';
import '../providers/role_management_provider.dart';

class RolesPermissionsSection extends ConsumerWidget {
  const RolesPermissionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataState = ref.watch(roleManagementProvider);
    final saving = ref.watch(roleManagementControllerProvider).isLoading;
    final offline = dataState.when(
      data: (data) => data.isOffline,
      error: (_, _) => false,
      loading: () => false,
    );
    final readOnly = saving || offline;
    final data = dataState.asData?.value;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Roles & Permissions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Team access aur responsibilities manage karein',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      readOnly || data == null
                          ? null
                          : () => _createRole(context, ref, data),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Role'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            dataState.when(
              loading: () => const LinearProgressIndicator(),
              error:
                  (error, _) => _ErrorRow(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(roleManagementProvider),
                  ),
              data:
                  (data) => Column(
                    children: [
                      if (data.isOffline) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Offline cached access dikhaya ja raha hai. Security changes ke liye internet required hai.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (final role in data.roles)
                        _RoleTile(
                          role: role,
                          assignmentCount: data.assignmentCount(role.id),
                          busy: readOnly,
                          onRename: () => _renameRole(context, ref, role),
                          onPermissions:
                              () => _editPermissions(context, ref, data, role),
                          onToggle: () => _toggleRole(context, ref, data, role),
                        ),
                      const Divider(height: 28),
                      _UserAssignments(
                        data: data,
                        busy: readOnly,
                        onInvite: () => _inviteStaff(context, ref, data),
                        onAssign:
                            (userId, roleId) =>
                                _assignUser(context, ref, userId, roleId),
                        onManageBranches:
                            (user) =>
                                _manageUserBranches(context, ref, data, user),
                      ),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRole(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
  ) async {
    final values = await _roleDialog(
      context,
      title: 'Create custom role',
      permissions: data.permissions,
    );
    if (values == null || !context.mounted) return;
    await _run(context, ref, (repository) {
      return repository.createRole(
        name: values.name,
        description: values.description,
        permissionKeys: values.permissionKeys,
      );
    });
  }

  Future<void> _renameRole(
    BuildContext context,
    WidgetRef ref,
    ManagedRole role,
  ) async {
    final values = await _roleDialog(
      context,
      title: 'Rename custom role',
      role: role,
    );
    if (values == null || !context.mounted) return;
    await _run(context, ref, (repository) {
      return repository.renameRole(
        roleId: role.id,
        name: values.name,
        description: values.description,
      );
    });
  }

  Future<void> _editPermissions(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
    ManagedRole role,
  ) async {
    final selected = {...role.permissionKeys};
    final result = await showDialog<Set<String>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('${role.name} permissions'),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final entry in data.permissionsByModule.entries)
                            ExpansionTile(
                              initiallyExpanded: true,
                              title: Text(_moduleLabel(entry.key)),
                              children: [
                                for (final permission in entry.value)
                                  CheckboxListTile(
                                    dense: true,
                                    value: selected.contains(permission.key),
                                    title: Text(permission.name),
                                    subtitle:
                                        permission.description == null
                                            ? null
                                            : Text(permission.description!),
                                    onChanged:
                                        (checked) => setState(() {
                                          if (checked == true) {
                                            selected.add(permission.key);
                                          } else {
                                            selected.remove(permission.key);
                                          }
                                        }),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, selected),
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      ref,
      (repository) => repository.updatePermissions(role.id, result),
    );
  }

  Future<void> _assignUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String roleId,
  ) {
    return _run(
      context,
      ref,
      (repository) => repository.assignUser(userId, roleId),
    );
  }

  Future<void> _manageUserBranches(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
    ManagedUserRole user,
  ) async {
    final selected = {
      for (final branch in data.branches)
        branch.id: data.branchRoleId(user.userId, branch.id),
    };
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('${user.fullName} branch access'),
                  content: SizedBox(
                    width: 430,
                    child:
                        data.branches.isEmpty
                            ? const Text('Is shop mein koi branch nahi mili.')
                            : ListView.separated(
                              shrinkWrap: true,
                              itemCount: data.branches.length,
                              separatorBuilder:
                                  (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final branch = data.branches[index];
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: selected[branch.id] ?? '',
                                      decoration: InputDecoration(
                                        labelText: branch.name,
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('No access'),
                                        ),
                                        for (final role
                                            in RoleManagementRules.assignableStaffRoles(
                                              data,
                                            ))
                                          DropdownMenuItem(
                                            value: role.id,
                                            child: Text(role.name),
                                          ),
                                      ],
                                      onChanged: (value) async {
                                        final roleId =
                                            value == null || value.isEmpty
                                                ? null
                                                : value;
                                        final success = await _run(
                                          context,
                                          ref,
                                          (repository) =>
                                              repository.setUserBranchRole(
                                                userId: user.userId,
                                                branchId: branch.id,
                                                roleId: roleId,
                                              ),
                                        );
                                        if (success && context.mounted) {
                                          setState(() {
                                            selected[branch.id] = roleId;
                                          });
                                        }
                                      },
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed:
                                            selected[branch.id] == null
                                                ? null
                                                : () =>
                                                    _editBranchPermissionOverrides(
                                                      context,
                                                      ref,
                                                      data,
                                                      user,
                                                      branch,
                                                    ),
                                        icon: const Icon(
                                          Icons.tune_rounded,
                                          size: 17,
                                        ),
                                        label: const Text(
                                          'Customize permissions',
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Done'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _editBranchPermissionOverrides(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
    ManagedUserRole user,
    ManagedBranch branch,
  ) async {
    final selected = Map<String, bool>.from(
      data.branchOverrides(user.userId, branch.id),
    );
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('${branch.name} permission overrides'),
                  content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const Text(
                            'Inherit role default rakhein, ya sirf is user aur branch ke liye allow/deny karein.',
                          ),
                          const SizedBox(height: 10),
                          for (final entry in data.permissionsByModule.entries)
                            ExpansionTile(
                              title: Text(_moduleLabel(entry.key)),
                              children: [
                                for (final permission in entry.value)
                                  ListTile(
                                    dense: true,
                                    title: Text(permission.name),
                                    subtitle:
                                        permission.description == null
                                            ? null
                                            : Text(permission.description!),
                                    trailing: SizedBox(
                                      width: 145,
                                      child: DropdownButtonFormField<String>(
                                        initialValue:
                                            selected.containsKey(permission.key)
                                                ? selected[permission.key]!
                                                    ? 'allow'
                                                    : 'deny'
                                                : 'inherit',
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'inherit',
                                            child: Text('Inherit role'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'allow',
                                            child: Text('Allow'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'deny',
                                            child: Text('Deny'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == 'allow') {
                                              selected[permission.key] = true;
                                            } else if (value == 'deny') {
                                              selected[permission.key] = false;
                                            } else {
                                              selected.remove(permission.key);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          () => Navigator.pop(
                            dialogContext,
                            Map<String, bool>.from(selected),
                          ),
                      child: const Text('Save overrides'),
                    ),
                  ],
                ),
          ),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      ref,
      (repository) => repository.replaceUserBranchPermissionOverrides(
        userId: user.userId,
        branchId: branch.id,
        overrides: result,
      ),
    );
  }

  Future<void> _inviteStaff(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
  ) async {
    final values = await _staffInvitationDialog(context, data);
    if (values == null || !context.mounted) return;
    final success = await _run(context, ref, (repository) {
      return repository.inviteStaff(
        fullName: values.fullName,
        email: values.email,
        roleId: values.roleId,
        branchRoles: values.branchRoles,
      );
    });
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation ${values.email} ko send ho gayi.')),
      );
    }
  }

  Future<void> _toggleRole(
    BuildContext context,
    WidgetRef ref,
    RoleManagementData data,
    ManagedRole role,
  ) async {
    if (!role.isActive) {
      await _run(
        context,
        ref,
        (repository) => repository.setRoleActive(role.id, true),
      );
      return;
    }

    final assignedCount = data.assignmentCount(role.id);
    String? replacementRoleId;
    if (assignedCount > 0) {
      replacementRoleId = await _replacementDialog(context, data, role);
      if (replacementRoleId == null || !context.mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text('${role.name} deactivate karein?'),
              content: const Text(
                'Role baad mein dobara reactivate kiya ja sakta hai.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Deactivate'),
                ),
              ],
            ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    await _run(context, ref, (repository) async {
      if (replacementRoleId != null) {
        await repository.moveUsers(role.id, replacementRoleId);
      }
      await repository.setRoleActive(role.id, false);
    });
  }

  Future<bool> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(RoleManagementRepository repository) action,
  ) async {
    final success = await ref
        .read(roleManagementControllerProvider.notifier)
        .run((repository) => action(repository));
    if (!context.mounted) return success;
    final state = ref.read(roleManagementControllerProvider);
    if (!success) {
      final message = state.whenOrNull(error: (error, _) => error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Role update nahi ho saka')),
      );
    }
    return success;
  }
}

class _RoleTile extends StatelessWidget {
  final ManagedRole role;
  final int assignmentCount;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onPermissions;
  final VoidCallback onToggle;

  const _RoleTile({
    required this.role,
    required this.assignmentCount,
    required this.busy,
    required this.onRename,
    required this.onPermissions,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surfaceVariant,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          role.isProtectedOwner ? Icons.shield_rounded : Icons.badge_outlined,
          color: role.isActive ? AppColors.primary : AppColors.textHint,
        ),
        title: Row(
          children: [
            Flexible(child: Text(role.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            _Tag(role.isSystem ? 'System' : 'Custom'),
            if (!role.isActive) ...[
              const SizedBox(width: 5),
              const _Tag('Inactive'),
            ],
          ],
        ),
        subtitle: Text(
          '$assignmentCount users • ${role.permissionKeys.length} permissions',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (role.description?.isNotEmpty == true)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(role.description!),
            ),
          const SizedBox(height: 8),
          if (!RoleManagementRules.canModify(role))
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Owner role protected hai aur deactivate nahi ho sakta.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!role.isSystem)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRename,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Rename'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onPermissions,
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('Permissions'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onToggle,
                  icon: Icon(
                    role.isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle,
                    size: 17,
                  ),
                  label: Text(role.isActive ? 'Deactivate' : 'Reactivate'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UserAssignments extends StatelessWidget {
  final RoleManagementData data;
  final bool busy;
  final VoidCallback onInvite;
  final Future<void> Function(String userId, String roleId) onAssign;
  final Future<void> Function(ManagedUserRole user) onManageBranches;

  const _UserAssignments({
    required this.data,
    required this.busy,
    required this.onInvite,
    required this.onAssign,
    required this.onManageBranches,
  });

  @override
  Widget build(BuildContext context) {
    final activeRoles = data.roles.where((role) => role.isActive).toList();
    final activeIds = activeRoles.map((role) => role.id).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'User assignments',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy || RoleManagementRules.assignableStaffRoles(data).isEmpty
                      ? null
                      : onInvite,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: const Text('Invite User'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final user in data.users)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user.fullName),
            subtitle: Text(user.email),
            trailing: SizedBox(
              width: 250,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          activeIds.contains(user.roleId) ? user.roleId : null,
                      hint: const Text('Tenant role'),
                      items: [
                        for (final role in activeRoles)
                          DropdownMenuItem(
                            value: role.id,
                            child: Text(role.name),
                          ),
                      ],
                      onChanged:
                          busy
                              ? null
                              : (roleId) {
                                if (roleId != null && roleId != user.roleId) {
                                  onAssign(user.userId, roleId);
                                }
                              },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Branch access',
                    onPressed:
                        busy ||
                                data.branches.isEmpty ||
                                data.roles.any(
                                  (role) =>
                                      role.id == user.roleId &&
                                      role.isProtectedOwner,
                                )
                            ? null
                            : () => onManageBranches(user),
                    icon: const Icon(Icons.storefront_outlined),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );
}

class _ErrorRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRow({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(message, style: const TextStyle(color: AppColors.error)),
      ),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

class _RoleDialogValue {
  final String name;
  final String? description;
  final Set<String> permissionKeys;
  const _RoleDialogValue(this.name, this.description, this.permissionKeys);
}

class _StaffInvitationValue {
  final String fullName;
  final String email;
  final String roleId;
  final Map<String, String> branchRoles;

  const _StaffInvitationValue(
    this.fullName,
    this.email,
    this.roleId,
    this.branchRoles,
  );
}

Future<_StaffInvitationValue?> _staffInvitationDialog(
  BuildContext context,
  RoleManagementData data,
) async {
  final roles = RoleManagementRules.assignableStaffRoles(data);
  if (roles.isEmpty) return null;
  var fullName = '';
  var email = '';
  String roleId = roles.first.id;
  final branchRoles = <String, String>{};
  final formKey = GlobalKey<FormState>();

  return showDialog<_StaffInvitationValue>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: const Text('Invite staff user'),
                content: SizedBox(
                  width: 480,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (value) => fullName = value,
                            validator:
                                (value) =>
                                    value?.trim().isEmpty ?? true
                                        ? 'Full name required hai'
                                        : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            onChanged: (value) => email = value,
                            validator: (value) {
                              final normalized = value?.trim() ?? '';
                              return RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(normalized)
                                  ? null
                                  : 'Valid email required hai';
                            },
                          ),
                          const SizedBox(height: 14),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Branch access',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final branch in data.branches) ...[
                            DropdownButtonFormField<String>(
                              initialValue: '',
                              decoration: InputDecoration(
                                labelText: branch.name,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('No access'),
                                ),
                                for (final role in roles)
                                  DropdownMenuItem(
                                    value: role.id,
                                    child: Text(role.name),
                                  ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  if (value == null || value.isEmpty) {
                                    branchRoles.remove(branch.id);
                                  } else {
                                    branchRoles[branch.id] = value;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (branchRoles.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Kam az kam aik branch ka role select karein.',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        branchRoles.isEmpty
                            ? null
                            : () {
                              if (!formKey.currentState!.validate()) return;
                              roleId = branchRoles.values.first;
                              Navigator.pop(
                                dialogContext,
                                _StaffInvitationValue(
                                  fullName.trim(),
                                  email.trim().toLowerCase(),
                                  roleId,
                                  Map<String, String>.from(branchRoles),
                                ),
                              );
                            },
                    child: const Text('Send Invite'),
                  ),
                ],
              ),
        ),
  );
}

Future<_RoleDialogValue?> _roleDialog(
  BuildContext context, {
  required String title,
  ManagedRole? role,
  List<ManagedPermission>? permissions,
}) async {
  var roleName = role?.name ?? '';
  var roleDescription = role?.description ?? '';
  final selectedPermissions = <String>{};
  final permissionsByModule = <String, List<ManagedPermission>>{};
  for (final permission in permissions ?? const <ManagedPermission>[]) {
    permissionsByModule
        .putIfAbsent(permission.module, () => [])
        .add(permission);
  }
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<_RoleDialogValue>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 560,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            initialValue: roleName,
                            decoration: const InputDecoration(
                              labelText: 'Role name',
                            ),
                            onChanged: (value) => roleName = value,
                            validator:
                                (value) =>
                                    value?.trim().isEmpty ?? true
                                        ? 'Role name required hai'
                                        : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: roleDescription,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                            ),
                            onChanged: (value) => roleDescription = value,
                            maxLines: 2,
                          ),
                          if (permissionsByModule.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (final entry in permissionsByModule.entries)
                              ExpansionTile(
                                initiallyExpanded: true,
                                title: Text(_moduleLabel(entry.key)),
                                children: [
                                  for (final permission in entry.value)
                                    CheckboxListTile(
                                      dense: true,
                                      value: selectedPermissions.contains(
                                        permission.key,
                                      ),
                                      title: Text(permission.name),
                                      subtitle:
                                          permission.description == null
                                              ? null
                                              : Text(permission.description!),
                                      onChanged: (checked) {
                                        setState(() {
                                          if (checked == true) {
                                            selectedPermissions.add(
                                              permission.key,
                                            );
                                          } else {
                                            selectedPermissions.remove(
                                              permission.key,
                                            );
                                          }
                                        });
                                      },
                                    ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(
                        dialogContext,
                        _RoleDialogValue(
                          roleName.trim(),
                          roleDescription.trim().isEmpty
                              ? null
                              : roleDescription.trim(),
                          Set<String>.from(selectedPermissions),
                        ),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
        ),
  );
  return result;
}

Future<String?> _replacementDialog(
  BuildContext context,
  RoleManagementData data,
  ManagedRole role,
) async {
  final replacements = RoleManagementRules.replacementRoles(data, role);
  String? selected = replacements.isEmpty ? null : replacements.first.id;
  return showDialog<String>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: Text('${role.name} users reassign karein'),
                content: DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Replacement role',
                  ),
                  items: [
                    for (final candidate in replacements)
                      DropdownMenuItem(
                        value: candidate.id,
                        child: Text(candidate.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => selected = value),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        selected == null
                            ? null
                            : () => Navigator.pop(dialogContext, selected),
                    child: const Text('Reassign & Deactivate'),
                  ),
                ],
              ),
        ),
  );
}

String _moduleLabel(String module) => module
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
