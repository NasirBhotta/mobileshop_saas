import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/login_screen.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/signup_screen.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mobileshop_saas/features/expenses/presentation/screens/expense_form_screen.dart';
import 'package:mobileshop_saas/features/expenses/presentation/screens/expense_report_screen.dart';
import 'package:mobileshop_saas/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:mobileshop_saas/features/expenses/presentation/screens/recurring_expense_form_screen.dart';
import 'package:mobileshop_saas/features/expenses/presentation/screens/recurring_expenses_screen.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/categories_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/csv_import_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/product_form_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/stock_adjustment_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/app_intro_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/branch_selection_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/shop_setup_screen.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/customers_screen.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/held_carts_screen.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/pos_screen.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/receipt_reprint_screen.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/return_screen.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/sale_complete_screen.dart';
import 'package:mobileshop_saas/features/repairs/presentation/screens/repair_form_screen.dart';
import 'package:mobileshop_saas/features/repairs/presentation/screens/repairs_list_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/business_dashboard_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/business_report_schedule_form_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/business_report_schedules_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/cash_flow_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/customer_credit_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/inventory_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/profit_loss_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/repair_report_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/reports_home_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/sales_report_schedule_form_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/sales_report_schedules_screen.dart';
import 'package:mobileshop_saas/features/reports/presentation/screens/sales_report_screen.dart';
import 'package:mobileshop_saas/features/reports/domain/report_entitlement_gate.dart';
import 'package:mobileshop_saas/features/settings/presentation/screens/account_settings_screen.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/po_document_screen.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/purchase_order_form_screen.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/purchase_orders_screen.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/receive_goods_screen.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/supplier_form_screen.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/screens/suppliers_screen.dart';
import 'package:mobileshop_saas/shared/widgets/app_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/core/entitlements/locked_feature_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_suspended_screen.dart';

final profileCompleteProvider = FutureProvider<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  final status = await ref
      .read(setupFlowRepositoryProvider)
      .loadStatus(user.id);
  return status.target != SetupRouteTarget.setup;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  ref.watch(entitlementRealtimeRefreshProvider);
  final tenantAccessRefresh = ref.watch(tenantAccessRefreshProvider);
  final entitlementRouterRefresh = ref.watch(entitlementRouterRefreshProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([
      tenantAccessRefresh,
      entitlementRouterRefresh,
    ]),
    redirect: (context, state) async {
      final location = state.uri.path;

      final prefs = await SharedPreferences.getInstance();

      final seenIntro = prefs.getBool('intro_seen') ?? false;

      if (!seenIntro) {
        return location == '/intro' ? null : '/intro';
      }

      if (location == '/intro') {
        return '/';
      }

      final session = Supabase.instance.client.auth.currentSession;
      final isAuthRoute = location == '/login' || location == '/signup';

      if (session == null) {
        return isAuthRoute ? null : '/login';
      }

      if (isAuthRoute) {
        return '/';
      }

      final tenantAccess = await ref.read(tenantAccessProvider.future);
      if (tenantAccess.isBlocked) {
        return location == '/account-suspended' ? null : '/account-suspended';
      }
      if (location == '/account-suspended') return '/dashboard';

      debugPrint("Router evaluating: ${state.uri.path}");

      final setupStatus = await ref
          .read(setupFlowRepositoryProvider)
          .loadStatus(session.user.id);

      debugPrint("Router target: ${setupStatus.target}");

      if (setupStatus.target == SetupRouteTarget.setup) {
        return location == '/setup' ? null : '/setup';
      }

      if (setupStatus.target == SetupRouteTarget.branchSelection) {
        return location == '/select-branch' ? null : '/select-branch';
      }

      if (location == '/select-branch' && setupStatus.branches.length >= 2) {
        return null;
      }

      if (location == '/' ||
          location == '/setup' ||
          location == '/select-branch') {
        return '/dashboard';
      }

      if (location != '/locked-feature') {
        final featureKey = requiredFeatureForLocation(location);
        if (featureKey != null) {
          final evaluator = ref.read(entitlementEvaluatorProvider);
          final enabled =
              featureKey.startsWith('reports.')
                  ? await ReportEntitlementGate(evaluator).allows(featureKey)
                  : await hasFeatureWithCompatibility(evaluator, featureKey);
          if (!enabled) {
            return Uri(
              path: '/locked-feature',
              queryParameters: {'feature': featureKey},
            ).toString();
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => null),
      GoRoute(
        path: '/intro',
        builder: (context, state) => const AppIntroScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/account-suspended',
        builder: (context, state) => const TenantSuspendedScreen(),
      ),
      // Email verification screen is temporarily disabled during development.
      // Re-enable this route when email confirmation is turned back on.
      // GoRoute(
      //   path: '/verify-email',
      //   builder:
      //       (context, state) => EmailVerificationPendingScreen(
      //         email: state.uri.queryParameters['email'] ?? '',
      //       ),
      // ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ShopSetupScreen(),
      ),

      GoRoute(
        path: '/select-branch',
        builder: (context, state) => const BranchSelectionScreen(),
      ),
      GoRoute(
        path: '/locked-feature',
        builder:
            (context, state) => LockedFeatureScreen(
              featureKey: state.uri.queryParameters['feature'] ?? 'unknown',
            ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AppLayout(
            currentIndex: _shellIndexForLocation(state.uri.path),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (_, _) => const InventoryScreen(),
          ),
          GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
          GoRoute(
            path: '/customers',
            builder: (_, _) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/customers/detail',
            builder: (context, state) {
              final customer = state.extra;
              if (customer is! CustomerModel) return const CustomersScreen();
              return CustomerDetailScreen(customer: customer);
            },
          ),
          GoRoute(
            path: '/repairs',
            builder: (context, state) {
              return const RepairsListScreen();
            },
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) {
              return const SuppliersScreen();
            },
          ),
          GoRoute(
            path: '/purchase-orders',
            builder: (context, state) {
              return const PurchaseOrdersScreen();
            },
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) {
              return const AccountsScreen();
            },
          ),
          GoRoute(
            path: '/expenses',
            builder: (context, state) {
              return const ExpensesScreen();
            },
          ),
          GoRoute(
            path: '/expenses/new',
            builder: (context, state) {
              return const ExpenseFormScreen();
            },
          ),
          GoRoute(
            path: '/expenses/report',
            builder: (context, state) {
              return const ExpenseReportScreen();
            },
          ),
          GoRoute(
            path: '/expenses/recurring',
            builder: (context, state) {
              return const RecurringExpensesScreen();
            },
          ),
          GoRoute(
            path: '/expenses/recurring/new',
            builder: (context, state) {
              return const RecurringExpenseFormScreen();
            },
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) {
              return const AccountSettingsScreen();
            },
          ),
          GoRoute(
            path: '/reports/sales',
            builder: (context, state) {
              return const SalesReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/sales/schedules',
            builder: (context, state) {
              return const SalesReportSchedulesScreen();
            },
          ),

          GoRoute(
            path: '/reports/sales/schedules/new',
            builder: (context, state) {
              return const SalesReportScheduleFormScreen();
            },
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) {
              return const ReportsHomeScreen();
            },
          ),

          GoRoute(
            path: '/reports/business',
            builder: (context, state) {
              return const BusinessDashboardReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/profit-loss',
            builder: (context, state) {
              return const ProfitLossReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/inventory',
            builder: (context, state) {
              return const InventoryReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/customer-credit',
            builder: (context, state) {
              return const CustomerCreditReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/cash-flow',
            builder: (context, state) {
              return const CashFlowReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/repairs',
            builder: (context, state) {
              return const RepairReportScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/schedules',
            builder: (context, state) {
              return const BusinessReportSchedulesScreen();
            },
          ),

          GoRoute(
            path: '/reports/business/schedules/new',
            builder: (context, state) {
              return const BusinessReportScheduleFormScreen();
            },
          ),
          GoRoute(
            path: '/reports/profit-loss',
            redirect: (_, _) => '/reports/business/profit-loss',
          ),
          GoRoute(
            path: '/reports/inventory',
            redirect: (_, _) => '/reports/business/inventory',
          ),
          GoRoute(
            path: '/reports/customer-credit',
            redirect: (_, _) => '/reports/business/customer-credit',
          ),
          GoRoute(
            path: '/reports/cash-flow',
            redirect: (_, _) => '/reports/business/cash-flow',
          ),
          GoRoute(
            path: '/reports/repairs',
            redirect: (_, _) => '/reports/business/repairs',
          ),
          GoRoute(
            path: '/reports/schedules',
            redirect: (_, _) => '/reports/business/schedules',
          ),
          GoRoute(
            path: '/reports/schedules/new',
            redirect: (_, _) => '/reports/business/schedules/new',
          ),
        ],
      ),
      GoRoute(path: '/expenses/add', redirect: (_, _) => '/expenses/new'),
      GoRoute(
        path: '/inventory/add',
        builder: (_, _) => const ProductFormScreen(),
      ),
      GoRoute(
        path: '/inventory/edit',
        builder:
            (context, state) =>
                ProductFormScreen(product: state.extra as ProductModel?),
      ),
      GoRoute(
        path: '/inventory/categories',
        builder: (_, _) => const CategoriesScreen(), // next step mein banayenge
      ),
      GoRoute(
        path: '/inventory/adjust',
        builder:
            (context, state) =>
                StockAdjustmentScreen(product: state.extra as ProductModel),
      ),
      GoRoute(
        path: '/inventory/import',
        builder: (_, _) => const CsvImportScreen(),
      ),
      GoRoute(path: '/pos/return', builder: (_, _) => const ReturnScreen()),
      GoRoute(
        path: '/pos/reprint',
        builder: (_, _) => const ReceiptReprintScreen(),
      ),
      GoRoute(
        path: '/pos/complete',
        builder: (context, state) {
          final sale = state.extra;
          if (sale is! SaleModel) return const PosScreen();
          return SaleCompleteScreen(sale: sale);
        },
      ),
      GoRoute(path: '/pos/held', builder: (_, _) => const HeldCartsScreen()),

      GoRoute(
        path: '/repairs/new',
        builder: (context, state) {
          return const RepairFormScreen();
        },
      ),

      GoRoute(
        path: '/suppliers/new',
        builder: (context, state) {
          return const SupplierFormScreen();
        },
      ),

      GoRoute(
        path: '/purchase-orders/new',
        builder: (context, state) {
          final supplier =
              state.extra is SupplierModel
                  ? state.extra as SupplierModel
                  : null;

          return PurchaseOrderFormScreen(initialSupplier: supplier);
        },
      ),

      GoRoute(
        path: '/purchase-orders/receive',
        builder: (context, state) {
          final po = state.extra as PurchaseOrderModel;

          return ReceiveGoodsScreen(po: po);
        },
      ),

      GoRoute(
        path: '/purchase-orders/export',
        builder: (context, state) {
          final po = state.extra as PurchaseOrderModel;

          return PODocumentScreen(po: po);
        },
      ),
    ],
  );
});

int _shellIndexForLocation(String location) {
  if (location.startsWith('/pos')) return 1;
  if (location.startsWith('/inventory')) return 2;
  if (location.startsWith('/customers')) return 3;
  if (location.startsWith('/repairs')) return 4;
  if (location.startsWith('/suppliers')) return 5;
  if (location.startsWith('/purchase-orders')) return 5;
  if (location.startsWith('/expenses')) return 6;
  if (location.startsWith('/accounts')) return 7;
  if (location.startsWith('/reports')) return 8;
  if (location.startsWith('/settings')) return 9;
  return 0;
}
