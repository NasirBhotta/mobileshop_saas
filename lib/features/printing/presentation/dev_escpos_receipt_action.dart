import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/data/models/sale_model.dart';
import '../../settings/presentation/providers/receipt_settings_provider.dart';
import '../domain/printer_adapter.dart';
import '../escpos/escpos_config.dart';
import '../escpos/printer_factory.dart';
import '../integrations/sale_receipt_mapper.dart';
import 'dev_receipt_sample.dart';

/// DEV ONLY: Escpresso receipt emulator integration.
/// This widget is the sole composition root. No global printer registration.
class DevEscPosReceiptAction extends ConsumerStatefulWidget {
  final SaleModel? sale;
  final String? footer;
  final PrinterAdapter? printer;

  const DevEscPosReceiptAction({
    super.key,
    this.sale,
    this.footer,
    this.printer,
  });

  @override
  ConsumerState<DevEscPosReceiptAction> createState() =>
      _DevEscPosReceiptActionState();
}

class _DevEscPosReceiptActionState
    extends ConsumerState<DevEscPosReceiptAction> {
  PrinterAdapter? _printer;
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.android);
    if (!kDebugMode || !EscPosConfig.devEnabled || !supported) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<bool>(
      enabled: !_printing,
      tooltip: 'ESC/POS receipt test - Dev',
      icon:
          _printing
              ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.science_outlined),
      onSelected: _print,
      itemBuilder:
          (_) => [
            const PopupMenuItem(value: true, child: Text('Test Receipt - Dev')),
            PopupMenuItem(
              value: false,
              enabled: widget.sale != null,
              child: const Text('Print selected receipt - Dev'),
            ),
          ],
    );
  }

  Future<void> _print(bool sample) async {
    if (_printing) return;
    setState(() => _printing = true);
    PrinterResult result;
    try {
      final sale = widget.sale;
      final receipt =
          sample
              ? devReceiptSample()
              : SaleReceiptMapper.map(
                sale!,
                await ref.read(receiptConfigurationProvider.future),
                footer: widget.footer,
              );
      _printer ??= widget.printer ?? createDevPrinter();
      result = await _printer!.printReceipt(receipt);
    } catch (error) {
      result = PrinterResult.failed(
        PrinterFailure.generationFailed,
        'Failed to prepare test receipt: $error',
      );
    }
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }
}
