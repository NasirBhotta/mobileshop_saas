import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/sale_model.dart';
import '../../data/services/receipt_service.dart';
import '../providers/pos_provider.dart';

class ReceiptReprintScreen extends ConsumerStatefulWidget {
  const ReceiptReprintScreen({super.key});

  @override
  ConsumerState<ReceiptReprintScreen> createState() =>
      _ReceiptReprintScreenState();
}

class _ReceiptReprintScreenState extends ConsumerState<ReceiptReprintScreen> {
  final _invoiceController = TextEditingController();
  SaleModel? _sale;
  bool _isSearching = false;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final footer = ref
        .watch(receiptFooterProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reprint Receipt'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice ID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _isSearching ? null : _search,
                icon:
                    _isSearching
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.search_rounded),
                label: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_sale != null) ...[
            Text(
              ReceiptService.formatReceipt(
                sale: _sale!,
                footer: footer,
                duplicate: true,
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final method in ReceiptDeliveryMethod.values)
                  OutlinedButton.icon(
                    onPressed:
                        () => ReceiptService.deliver(
                          sale: _sale!,
                          method: method,
                          footer: footer,
                          duplicate: true,
                        ),
                    icon: Icon(_iconFor(method)),
                    label: Text(method.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _search() async {
    setState(() => _isSearching = true);
    try {
      final sale = await ref
          .read(posRepositoryProvider)
          .findSaleForReturn(_invoiceController.text);
      if (!mounted) return;
      setState(() => _sale = sale);
      if (sale == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice nahi mila'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  IconData _iconFor(ReceiptDeliveryMethod method) {
    switch (method) {
      case ReceiptDeliveryMethod.thermalPrint:
        return Icons.print_rounded;
      case ReceiptDeliveryMethod.whatsapp:
        return Icons.chat_rounded;
      case ReceiptDeliveryMethod.email:
        return Icons.email_rounded;
    }
  }
}
