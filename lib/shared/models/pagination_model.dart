class PaginationModel {
  const PaginationModel({
    required this.page,
    required this.pageSize,
    required this.totalItems,
  });

  final int page;
  final int pageSize;
  final int totalItems;

  int get totalPages {
    if (pageSize == 0) {
      return 0;
    }

    return (totalItems / pageSize).ceil();
  }
}
