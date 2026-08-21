import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/constants/app_strings.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/repairs/presentation/providers/repair_provider.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_payment_model.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';
import '../../data/models/repair_ticket_model.dart';
import '../widgets/repair_completion_dialog.dart';

class RepairsListScreen extends ConsumerStatefulWidget {
  final RepairTicketModel? initialTicket;
  final String? initialTicketId;

  const RepairsListScreen({
    super.key,
    this.initialTicket,
    this.initialTicketId,
  });

  @override
  ConsumerState<RepairsListScreen> createState() => _RepairsListScreenState();
}

class _RepairsListScreenState extends ConsumerState<RepairsListScreen> {
  String? _openedInitialTicketId;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  List<RepairTicketModel>? _lastTickets;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(repairCustomerSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ref.read(repairCustomerSearchQueryProvider.notifier).state = value.trim();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(repairCustomerSearchQueryProvider.notifier).state = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var initialTicket = widget.initialTicket;
    final initialTicketId = widget.initialTicketId;
    if (initialTicket == null && initialTicketId != null) {
      final allTickets = ref.watch(allRepairTicketsProvider).value;
      if (allTickets != null) {
        for (final ticket in allTickets) {
          if (ticket.id == initialTicketId) {
            initialTicket = ticket;
            break;
          }
        }
      }
    }
    if (initialTicket != null && _openedInitialTicketId != initialTicket.id) {
      _openedInitialTicketId = initialTicket.id;
      final ticketToOpen = initialTicket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showTicketDetails(context, ref, ticketToOpen);
      });
    }

    final ticketsAsync = ref.watch(repairTicketsProvider);
    final visibleTicketsAsync =
        ticketsAsync.isLoading && _lastTickets != null
            ? AsyncValue<List<RepairTicketModel>>.data(_lastTickets!)
            : ticketsAsync;
    final selectedStatus = ref.watch(selectedRepairStatusFilterProvider);
    final syncState = ref.watch(repairSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.repairsTitle),
        actions: [
          IconButton(
            tooltip: AppStrings.repairSync,
            onPressed:
                syncState.isLoading
                    ? null
                    : () async {
                      await ref
                          .read(repairSyncControllerProvider.notifier)
                          .sync();
                    },
            icon:
                syncState.isLoading
                    ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/repairs/new'),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.repairNew),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Customer name se repair search karein',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon:
                      _searchController.text.isEmpty
                          ? null
                          : IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear search',
                          ),
                ),
              ),
            ),
            _RepairStatusFilterBar(
              selectedStatus: selectedStatus,
              onChanged: (status) {
                ref.read(selectedRepairStatusFilterProvider.notifier).state =
                    status;
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: visibleTicketsAsync.when(
                loading: () {
                  return const Center(child: CircularProgressIndicator());
                },
                error: (error, _) {
                  return _RepairErrorView(
                    message: error.toString(),
                    onRetry: () {
                      ref.invalidate(repairTicketsProvider);
                    },
                  );
                },
                data: (tickets) {
                  _lastTickets = tickets;
                  if (tickets.isEmpty) {
                    return RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(repairSyncControllerProvider.notifier)
                                  .sync(),
                      child: LayoutBuilder(
                        builder:
                            (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: _EmptyRepairsView(
                                    selectedStatus: selectedStatus,
                                    onCreate:
                                        () => context.push('/repairs/new'),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh:
                        () =>
                            ref
                                .read(repairSyncControllerProvider.notifier)
                                .sync(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        if (width >= 1024) {
                          // Desktop / Large screens (3-4 columns)
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 420,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  mainAxisExtent: 195,
                                ),
                            itemCount: tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = tickets[index];
                              return _RepairTicketCard(
                                ticket: ticket,
                                onTap: () {
                                  _showTicketDetails(context, ref, ticket);
                                },
                              );
                            },
                          );
                        } else if (width >= 600) {
                          // iPad / Tablet (2 columns)
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 195,
                                ),
                            itemCount: tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = tickets[index];
                              return _RepairTicketCard(
                                ticket: ticket,
                                onTap: () {
                                  _showTicketDetails(context, ref, ticket);
                                },
                              );
                            },
                          );
                        }

                        // Mobile (< 600px)
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: tickets.length,
                          separatorBuilder: (_, _) {
                            return const SizedBox(height: 10);
                          },
                          itemBuilder: (context, index) {
                            final ticket = tickets[index];
                            return _RepairTicketCard(
                              ticket: ticket,
                              onTap: () {
                                _showTicketDetails(context, ref, ticket);
                              },
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showTicketDetails(
    BuildContext context,
    WidgetRef ref,
    RepairTicketModel ticket,
  ) {
    final details = _RepairTicketDetails(
      ticket: ticket,
      onStatusChanged: ({
        required status,
        note,
        totalCost,
        refundAccountId,
      }) async {
        final controller = ref.read(repairTicketControllerProvider.notifier);
        final updatedTicket =
            status == RepairTicketStatus.cancelled
                ? await controller.cancelRepair(
                  ticket,
                  refundAccountId: refundAccountId,
                )
                : await controller.updateStatus(
                  ticket: ticket,
                  status: status,
                  note: note,
                  totalCost: totalCost,
                );

        if (updatedTicket == null) {
          final state = ref.read(repairTicketControllerProvider);
          final error = _friendlyRepairStatusError(state.asError?.error);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
          return false;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.repairStatusUpdated(status.label)),
            ),
          );
        }
        return true;
      },
    );

    if (!Responsive.isMobile(context)) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: details,
            ),
          );
        },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: details,
        );
      },
    );
  }
}

String _friendlyRepairStatusError(Object? error) {
  final message = error?.toString().toLowerCase() ?? '';
  if (message.contains('insufficient refund balance')) {
    return AppStrings.repairRefundBalanceLow;
  }
  if (message.contains('select an account') ||
      message.contains('refund account is not available')) {
    return AppStrings.repairRefundAccountRequired;
  }
  if (message.contains('resolve paid supplier amount')) {
    return AppStrings.repairSupplierPaidPartBlocked;
  }
  if (message.contains('permission') ||
      message.contains('not allowed') ||
      message.contains('42501')) {
    return AppStrings.repairCancelPermissionDenied;
  }
  return AppStrings.repairCancelFailed;
}

typedef _StatusChanged =
    Future<bool> Function({
      required RepairTicketStatus status,
      String? note,
      double? totalCost,
      String? refundAccountId,
    });

typedef _CancellationResolution = ({bool confirmed, String? accountId});

class _RepairTicketDetails extends ConsumerStatefulWidget {
  final RepairTicketModel ticket;
  final _StatusChanged onStatusChanged;

  const _RepairTicketDetails({
    required this.ticket,
    required this.onStatusChanged,
  });

  @override
  ConsumerState<_RepairTicketDetails> createState() =>
      _RepairTicketDetailsState();
}

class _RepairTicketDetailsState extends ConsumerState<_RepairTicketDetails> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();

  RepairTicketStatus? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final statuses = _nextStatuses(widget.ticket.status);
    _selectedStatus = statuses.isEmpty ? null : statuses.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final imei = ticket.imei?.trim();
    final estimatedCost = ticket.estimatedCost;
    final totalCost = ticket.totalCost;
    final statuses = _nextStatuses(ticket.status);
    final selectedStatus = _selectedStatus;
    final paymentsAsync = ref.watch(repairPaymentsProvider(ticket.id));
    final isReceivingPayment = ref.watch(
      repairPaymentControllerProvider.select((state) => state.isLoading),
    );
    final payments = paymentsAsync.value;
    final paid = payments?.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    final balance =
        totalCost == null || paid == null
            ? null
            : (totalCost - paid).clamp(0, double.infinity).toDouble();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isSaving) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_sync_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(AppStrings.repairStatusUpdating),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.ticketNo ?? AppStrings.repairTicketLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppStrings.repairClose,
                    onPressed:
                        _isSaving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                runSpacing: 6,
                children: [
                  _DetailLine(
                    label: AppStrings.repairCustomer,
                    value: ticket.customerName,
                  ),
                  _DetailLine(
                    label: AppStrings.repairDevice,
                    value: AppStrings.repairDeviceName(
                      ticket.deviceBrand,
                      ticket.deviceModel,
                    ),
                  ),
                  _DetailLine(
                    label: AppStrings.repairStatus,
                    value: ticket.status.label,
                  ),
                  if (imei != null && imei.isNotEmpty)
                    _DetailLine(label: AppStrings.repairImei, value: imei),
                  if (estimatedCost != null)
                    _DetailLine(
                      label: AppStrings.repairServiceEstimate,
                      value: AppStrings.repairMoney(estimatedCost),
                    ),
                  if (totalCost != null)
                    _DetailLine(
                      label: AppStrings.repairFinalBillLabel,
                      value: AppStrings.repairMoney(totalCost),
                    ),
                  _DetailLine(
                    label: AppStrings.repairReceive,
                    value:
                        paid == null
                            ? paymentsAsync.hasError
                                ? AppStrings.repairUnableToLoad
                                : AppStrings.loading
                            : AppStrings.repairMoney(paid),
                  ),
                  if (balance != null)
                    _DetailLine(
                      label: AppStrings.paymentRemaining,
                      value: AppStrings.repairMoney(balance),
                    ),
                ],
              ),
              if (totalCost != null &&
                  balance != null &&
                  balance > 0.009 &&
                  ticket.status != RepairTicketStatus.cancelled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      _isSaving || isReceivingPayment
                          ? null
                          : () => _showPaymentDialog(balance),
                  icon:
                      isReceivingPayment
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.payments_outlined),
                  label: Text(
                    isReceivingPayment
                        ? AppStrings.repairReceivingPayment
                        : AppStrings.repairReceivePayment,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                ticket.faultDescription,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (ticket.photoPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  AppStrings.repairDevicePhotos,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ticket.photoPaths.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final path = ticket.photoPaths[index];
                      final isLocal = File(path).existsSync();
                      return GestureDetector(
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogCtx) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(16),
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  InteractiveViewer(
                                    clipBehavior: Clip.none,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: isLocal
                                          ? Image.file(File(path), fit: BoxFit.contain)
                                          : Image.network(path, fit: BoxFit.contain),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.of(dialogCtx).pop(),
                                    icon: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(180),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: isLocal
                                ? Image.file(File(path), fit: BoxFit.cover)
                                : Image.network(
                                    path,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined, size: 20),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _archive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text(AppStrings.repairArchiveTicket),
              ),
              const SizedBox(height: 12),
              if (statuses.isEmpty)
                Text(
                  AppStrings.repairStatusLocked,
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else ...[
                DropdownButtonFormField<RepairTicketStatus>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: AppStrings.repairNextStatus,
                    border: OutlineInputBorder(),
                  ),
                  items:
                      statuses
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _isSaving
                          ? null
                          : (status) {
                            setState(() {
                              _selectedStatus = status;
                            });
                          },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  enabled: !_isSaving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: AppStrings.repairStatusNote,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _isSaving || selectedStatus == null
                          ? null
                          : () => _submit(selectedStatus),
                  icon:
                      _isSaving
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.done),
                  label: Text(
                    _isSaving
                        ? AppStrings.repairUpdating
                        : AppStrings.repairUpdateStatus,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(double remaining) async {
    List<AccountModel> availableAccounts;
    try {
      availableAccounts = await ref.read(accountsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.repairAccountsLoadFailed(error))),
      );
      return;
    }
    if (!mounted) return;

    final amountController = TextEditingController(
      text: remaining.toStringAsFixed(0),
    );
    final noteController = TextEditingController();
    var method = PaymentMethod.cash;
    String? accountId;
    var isReceiving = false;
    String? paymentError;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final compatible = PosPaymentAccountPolicy.compatibleAccounts(
                method,
                availableAccounts,
              );
              final effectiveAccountId =
                  accountId ??
                  PosPaymentAccountPolicy.suggestedAccount(
                    method,
                    compatible,
                  )?.id;
              return AlertDialog(
                title: const Text(AppStrings.repairReceivePaymentTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      enabled: !isReceiving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: AppStrings.repairAmount,
                        helperText: AppStrings.repairRemaining(remaining),
                      ),
                    ),
                    SizedBox(height: 10),
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: AppStrings.repairMethod,
                      ),
                      items:
                          PaymentMethod.values
                              .where((value) => value != PaymentMethod.credit)
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                      onChanged:
                          isReceiving
                              ? null
                              : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  method = value;
                                  accountId = null;
                                });
                              },
                    ),

                    SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: effectiveAccountId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppStrings.repairReceivingAccount,
                        helperText:
                            compatible.isEmpty
                                ? AppStrings.repairCompatibleAccountRequired
                                : null,
                      ),
                      items:
                          compatible
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account.id,
                                  child: Text(account.name),
                                ),
                              )
                              .toList(),
                      onChanged:
                          isReceiving || compatible.isEmpty
                              ? null
                              : (value) =>
                                  setDialogState(() => accountId = value),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      enabled: !isReceiving,
                      decoration: const InputDecoration(
                        labelText: AppStrings.repairPaymentNote,
                      ),
                    ),
                    if (paymentError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        paymentError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isReceiving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                    child: const Text(AppStrings.repairCancel),
                  ),
                  FilledButton(
                    onPressed:
                        isReceiving || effectiveAccountId == null
                            ? null
                            : () async {
                              final amount =
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0;
                              if (amount <= 0 || amount > remaining + 0.01) {
                                setDialogState(() {
                                  paymentError = AppStrings.repairAmountRange(
                                    remaining,
                                  );
                                });
                                return;
                              }
                              setDialogState(() {
                                isReceiving = true;
                                paymentError = null;
                              });
                              final ok = await ref
                                  .read(
                                    repairPaymentControllerProvider.notifier,
                                  )
                                  .recordPayment(
                                    ticket: widget.ticket,
                                    amount: amount,
                                    method: method.code,
                                    accountId: effectiveAccountId,
                                    note: noteController.text,
                                  );
                              if (!dialogContext.mounted || !mounted) return;
                              if (ok) {
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      AppStrings.repairPaymentReceived,
                                    ),
                                  ),
                                );
                              } else {
                                final error =
                                    ref
                                        .read(repairPaymentControllerProvider)
                                        .asError
                                        ?.error
                                        .toString() ??
                                    AppStrings.repairPaymentFailed;
                                setDialogState(() {
                                  isReceiving = false;
                                  paymentError = error;
                                });
                              }
                            },
                    child:
                        isReceiving
                            ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(AppStrings.repairReceiving),
                              ],
                            )
                            : const Text(AppStrings.repairReceive),
                  ),
                ],
              );
            },
          ),
    );
    amountController.dispose();
    noteController.dispose();
  }

  Future<void> _submit(RepairTicketStatus status) async {
    if (status == RepairTicketStatus.completed) {
      final completed = await showRepairCompletionDialog(
        context,
        ref,
        widget.ticket,
      );
      if (!mounted || !completed) return;
      Navigator.of(context).pop();
      return;
    }
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    String? refundAccountId;
    if (status == RepairTicketStatus.cancelled) {
      final resolution = await _showCancellationRefundDialog();
      if (!mounted || !resolution.confirmed) return;
      refundAccountId = resolution.accountId;
    }

    setState(() {
      _isSaving = true;
    });

    var updated = false;
    try {
      updated = await widget.onStatusChanged(
        status: status,
        note: _noteController.text,
        totalCost: null,
        refundAccountId: refundAccountId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.repairStatusUpdateFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }

    if (!mounted) return;
    if (updated) {
      Navigator.of(context).pop();
    }
  }

  Future<_CancellationResolution> _showCancellationRefundDialog() async {
    final results = await Future.wait<Object>([
      ref.read(repairPaymentsProvider(widget.ticket.id).future),
      ref.read(accountsProvider.future),
    ]);
    if (!mounted) return (confirmed: false, accountId: null);
    final payments = results[0] as List<RepairPaymentModel>;
    final paid = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    if (paid <= 0) return (confirmed: true, accountId: null);
    final accounts =
        (results[1] as List<AccountModel>)
            .where(
              (account) =>
                  account.isActive &&
                  account.branchId == widget.ticket.branchId &&
                  account.currentBalance + 0.01 >= paid,
            )
            .toList()
          ..sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            return a.name.compareTo(b.name);
          });
    String? accountId = accounts.isEmpty ? null : accounts.first.id;
    bool submitting = false;
    String? error;
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text(AppStrings.repairCancelRefundTitle),
                  content: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(AppStrings.repairRefundAmount(paid)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: accountId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: AppStrings.repairRefundAccount,
                            border: OutlineInputBorder(),
                          ),
                          items:
                              accounts
                                  .map(
                                    (account) => DropdownMenuItem(
                                      value: account.id,
                                      child: Text(
                                        AppStrings.repairAccountBalance(
                                          account.name,
                                          account.currentBalance,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              submitting
                                  ? null
                                  : (value) => setDialogState(() {
                                    accountId = value;
                                    error = null;
                                  }),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          AppStrings.repairRefundConfirmation,
                          style: TextStyle(fontSize: 12),
                        ),
                        if (accounts.isEmpty || error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error ?? AppStrings.repairRefundBalanceUnavailable,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          submitting
                              ? null
                              : () => Navigator.pop(dialogContext),
                      child: const Text(AppStrings.repairBack),
                    ),
                    FilledButton(
                      onPressed:
                          submitting || accountId == null
                              ? null
                              : () {
                                setDialogState(() => submitting = true);
                                Navigator.pop(dialogContext, accountId);
                              },
                      child: const Text(AppStrings.repairRefundAndCancel),
                    ),
                  ],
                ),
          ),
    );
    return (confirmed: selected != null, accountId: selected);
  }

  Future<void> _archive() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text(AppStrings.repairArchiveTitle),
                content: const Text(AppStrings.repairArchiveMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(AppStrings.repairBack),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text(AppStrings.repairArchive),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _isSaving = true);
    final archived = await ref
        .read(repairTicketControllerProvider.notifier)
        .archiveRepair(widget.ticket);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (archived) {
      Navigator.of(context).pop();
    }
  }

  static List<RepairTicketStatus> _nextStatuses(RepairTicketStatus current) {
    return RepairTicketStatus.values
        .where((status) => current.canMoveTo(status))
        .toList();
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: AppStrings.repairDetailLabel(label),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _RepairStatusFilterBar extends StatefulWidget {
  final RepairTicketStatus? selectedStatus;
  final ValueChanged<RepairTicketStatus?> onChanged;

  const _RepairStatusFilterBar({
    required this.selectedStatus,
    required this.onChanged,
  });

  @override
  State<_RepairStatusFilterBar> createState() => _RepairStatusFilterBarState();
}

class _RepairStatusFilterBarState extends State<_RepairStatusFilterBar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = <RepairTicketStatus?>[
      null,
      RepairTicketStatus.received,
      RepairTicketStatus.diagnosed,
      RepairTicketStatus.inProgress,
      RepairTicketStatus.waitingPart,
      RepairTicketStatus.completed,
      RepairTicketStatus.delivered,
      RepairTicketStatus.cancelled,
    ];
    return SizedBox(
      height: 56,
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || !_scrollController.hasClients) {
            return;
          }

          final delta =
              event.scrollDelta.dx == 0
                  ? event.scrollDelta.dy
                  : event.scrollDelta.dx;
          final position = _scrollController.position;
          final offset = (_scrollController.offset + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );

          _scrollController.jumpTo(offset);
        },
        child: ScrollConfiguration(
          behavior: const _StatusFilterScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                for (final status in statuses) ...[
                  FilterChip(
                    selected: widget.selectedStatus == status,
                    avatar:
                        status == null
                            ? null
                            : Icon(
                              Icons.circle,
                              size: 10,
                              color: _repairStatusColor(status),
                            ),
                    label: Text(
                      status == null ? AppStrings.repairAll : status.label,
                    ),
                    selectedColor:
                        status == null
                            ? null
                            : _repairStatusColor(
                              status,
                            ).withValues(alpha: 0.16),
                    side:
                        status == null
                            ? null
                            : BorderSide(
                              color: _repairStatusColor(
                                status,
                              ).withValues(alpha: 0.38),
                            ),
                    onSelected: (_) => widget.onChanged(status),
                  ),
                  if (status != statuses.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFilterScrollBehavior extends MaterialScrollBehavior {
  const _StatusFilterScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    return {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.unknown,
    };
  }
}

class _RepairTicketCard extends StatelessWidget {
  final RepairTicketModel ticket;
  final VoidCallback onTap;
  const _RepairTicketCard({required this.ticket, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final createdDate = _formatDate(ticket.createdAt);
    final imei = ticket.imei?.trim();
    final estimatedCost = ticket.estimatedCost;
    final estimate =
        estimatedCost == null
            ? null
            : AppStrings.repairServiceEstimateAmount(estimatedCost);
    final theme = Theme.of(context);
    final hasPhotos = ticket.photoPaths.isNotEmpty;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.ticketNo ?? AppStrings.repairNoTicketNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  _StatusBadge(status: ticket.status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AppStrings.repairDeviceName(
                            ticket.deviceBrand,
                            ticket.deviceModel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        if (imei != null && imei.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            AppStrings.repairImeiValue(imei),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          ticket.faultDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (hasPhotos)
                    _CardPhotoPreview(
                      photoPaths: ticket.photoPaths,
                    )
                  else
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.phone_android_rounded,
                          size: 26,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    createdDate,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (estimate != null) ...[
                    const Spacer(),
                    Text(
                      estimate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return AppStrings.repairNoDate;
    return AppStrings.repairDate(date);
  }
}

class _CardPhotoPreview extends StatelessWidget {
  final List<String> photoPaths;

  const _CardPhotoPreview({required this.photoPaths});

  @override
  Widget build(BuildContext context) {
    if (photoPaths.isEmpty) return const SizedBox.shrink();
    final firstPath = photoPaths.first;
    final isLocal = File(firstPath).existsSync();
    final extraCount = photoPaths.length - 1;

    return GestureDetector(
      onTap: () => _openZoomDialog(context, firstPath),
      child: Tooltip(
        message: 'Tap to zoom photo',
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                isLocal
                    ? Image.file(
                        File(firstPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 20),
                        ),
                      )
                    : Image.network(
                        firstPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 20),
                        ),
                      ),
                if (extraCount > 0)
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+$extraCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openZoomDialog(BuildContext context, String path) {
    final isLocal = File(path).existsSync();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              clipBehavior: Clip.none,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isLocal
                    ? Image.file(File(path), fit: BoxFit.contain)
                    : Image.network(path, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final RepairTicketStatus status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = _repairStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Color _repairStatusColor(RepairTicketStatus status) {
  return switch (status) {
    RepairTicketStatus.received => const Color(0xFF3E7CB1),
    RepairTicketStatus.diagnosed => const Color(0xFF7357A5),
    RepairTicketStatus.inProgress => const Color(0xFFD97706),
    RepairTicketStatus.waitingPart => const Color(0xFFC18B16),
    RepairTicketStatus.completed => const Color(0xFF1E9E64),
    RepairTicketStatus.delivered => const Color(0xFF087F8C),
    RepairTicketStatus.cancelled => const Color(0xFFD3543F),
  };
}

class _EmptyRepairsView extends StatelessWidget {
  final RepairTicketStatus? selectedStatus;
  final VoidCallback onCreate;
  const _EmptyRepairsView({
    required this.selectedStatus,
    required this.onCreate,
  });
  @override
  Widget build(BuildContext context) {
    final status = selectedStatus;
    final text =
        status == null
            ? AppStrings.repairsEmptyMessage
            : AppStrings.repairStatusEmpty(status.label);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.build_circle_outlined, size: 52),
              const SizedBox(height: 12),
              Text(
                AppStrings.repairsEmptyTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.repairCreateTicket),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepairErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RepairErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52),
              const SizedBox(height: 12),
              Text(
                AppStrings.repairsLoadFailed,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text(AppStrings.repairRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
