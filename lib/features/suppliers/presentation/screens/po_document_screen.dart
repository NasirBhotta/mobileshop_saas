import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';
import '../../data/models/procurement_models.dart';

class PODocumentScreen extends ConsumerWidget {
  final PurchaseOrderModel po;

  const PODocumentScreen({super.key, required this.po});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref
        .read(procurementRepositoryProvider)
        .buildPurchaseOrderDocument(po: po);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PO Document'),
        actions: [
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: document));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('PO copied')));
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Card(
              elevation: 0,
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  document,
                  style: const TextStyle(fontFamily: 'monospace', height: 1.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
