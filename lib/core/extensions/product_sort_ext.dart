import 'package:mobileshop_saas/core/constants/app_strings.dart';

enum ProductSortOption {
  nameAZ,
  nameZA,
  priceLow,
  priceHigh,
  stockLow,
  stockHigh,
}

extension ProductSortOptionX on ProductSortOption {
  String get label {
    switch (this) {
      case ProductSortOption.nameAZ:
        return AppStrings.sortNameAZ;
      case ProductSortOption.nameZA:
        return AppStrings.sortNameZA;
      case ProductSortOption.priceLow:
        return AppStrings.sortPriceLow;
      case ProductSortOption.priceHigh:
        return AppStrings.sortPriceHigh;
      case ProductSortOption.stockLow:
        return AppStrings.sortStockLow;
      case ProductSortOption.stockHigh:
        return AppStrings.sortStockHigh;
    }
  }
}
