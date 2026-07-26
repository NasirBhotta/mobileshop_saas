import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';
import 'dart:io';

void main() {
  const branches = [
    BranchInputModel(id: 'branch-a', name: 'Branch A'),
    BranchInputModel(id: 'branch-b', name: 'Branch B'),
    BranchInputModel(id: 'branch-c', name: 'Branch C'),
  ];

  test('unconfigured staff retains legacy branch list', () {
    const status = SetupFlowStatus(
      target: SetupRouteTarget.dashboard,
      profile: {'branch_id': 'branch-a'},
      branches: branches,
    );

    final filtered = filterSetupStatusForBranchAccess(
      status,
      configured: false,
      accessibleBranchIds: const {},
    );

    expect(filtered.branches, hasLength(3));
    expect(filtered.target, SetupRouteTarget.dashboard);
  });

  test('configured staff sees assigned branches only', () {
    const status = SetupFlowStatus(
      target: SetupRouteTarget.dashboard,
      profile: {'branch_id': 'branch-a'},
      branches: branches,
    );

    final filtered = filterSetupStatusForBranchAccess(
      status,
      configured: true,
      accessibleBranchIds: const {'branch-a', 'branch-c'},
    );

    expect(filtered.branches.map((branch) => branch.id), [
      'branch-a',
      'branch-c',
    ]);
    expect(filtered.target, SetupRouteTarget.dashboard);
  });

  test('unauthorized selected branch forces branch selection', () {
    const status = SetupFlowStatus(
      target: SetupRouteTarget.dashboard,
      profile: {'branch_id': 'branch-b'},
      branches: branches,
    );

    final filtered = filterSetupStatusForBranchAccess(
      status,
      configured: true,
      accessibleBranchIds: const {'branch-a'},
    );

    expect(filtered.branches.single.id, 'branch-a');
    expect(filtered.target, SetupRouteTarget.branchSelection);
  });

  test('staff with no active branch assignment has no selectable branch', () {
    const status = SetupFlowStatus(
      target: SetupRouteTarget.dashboard,
      profile: {'branch_id': 'branch-a'},
      branches: branches,
    );

    final filtered = filterSetupStatusForBranchAccess(
      status,
      configured: true,
      accessibleBranchIds: const {},
    );

    expect(filtered.branches, isEmpty);
    expect(filtered.target, SetupRouteTarget.branchSelection);
  });

  test('router and selection write path use accessible branch status', () {
    final router = File('lib/config/router/app_router.dart').readAsStringSync();
    final repository =
        File(
          'lib/features/onboarding/data/repositories/setup_flow_repository.dart',
        ).readAsStringSync();

    expect(router, contains('.restrictToAccessibleBranches(userId, status)'));
    expect(
      repository,
      contains('Selected branch is not assigned to this user.'),
    );
    expect(repository, contains('ref.watch(permissionRevisionProvider)'));
  });

  test('database blocks direct unauthorized branch selection', () {
    final sql =
        File(
          'supabase/migrations/20260726000500_enforce_branch_selection_access.sql',
        ).readAsStringSync();

    expect(sql, contains('public.enforce_user_branch_assignment_on_selection'));
    expect(sql, contains("new.role = 'owner'"));
    expect(sql, contains('configured.user_id = new.id'));
    expect(sql, contains('active_assignment.branch_id = new.branch_id'));
    expect(sql, contains('active_assignment.revoked_at is null'));
    expect(sql, contains("errcode = '42501'"));
  });
}
