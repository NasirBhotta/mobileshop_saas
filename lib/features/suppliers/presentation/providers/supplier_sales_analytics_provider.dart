import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/supplier_sales_analytics_models.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

typedef SupplierSummaryRequest =
    ({SupplierModel supplier, SupplierAnalyticsPeriod period});

typedef SupplierProductPageRequest =
    ({
      SupplierModel supplier,
      SupplierAnalyticsPeriod period,
      String search,
      SupplierProfitFilter filter,
      SupplierAnalyticsSort sort,
      int limit,
      int offset,
    });

final supplierSalesSummaryProvider = FutureProvider.autoDispose
    .family<SupplierSalesSummary, SupplierSummaryRequest>((ref, request) {
      return ref
          .read(procurementRepositoryProvider)
          .fetchSupplierSalesSummary(request.supplier, period: request.period);
    });

final supplierProductSalesPageProvider = FutureProvider.autoDispose
    .family<SupplierProductSalesPage, SupplierProductPageRequest>((
      ref,
      request,
    ) {
      return ref
          .read(procurementRepositoryProvider)
          .fetchSupplierProductSalesPage(
            request.supplier,
            period: request.period,
            search: request.search,
            profitFilter: request.filter,
            sort: request.sort,
            limit: request.limit,
            offset: request.offset,
          );
    });
