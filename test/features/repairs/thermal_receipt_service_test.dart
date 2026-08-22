import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/features/repairs/data/services/thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThermalReceiptService', () {
    final sampleTicket = RepairTicketModel(
      id: 'ticket-uuid-001',
      ticketNo: 'TK-2026-001',
      tenantId: 'tenant-123',
      branchId: 'branch-456',
      customerName: 'Usman Ghani',
      customerPhone: '0312-3456789',
      deviceBrand: 'Apple',
      deviceModel: 'iPhone 14 Pro Max',
      deviceColor: 'Deep Purple',
      imei: '354890102938475',
      faultDescription: 'Battery draining fast & back glass cracked.',
      status: RepairTicketStatus.inProgress,
      estimatedCost: 12000,
      technicianId: 'Zubair Tech',
      estimatedCompletionAt: DateTime(2026, 8, 25, 18, 0),
      createdBy: 'user-001',
      createdAt: DateTime(2026, 8, 22, 14, 30),
      updatedAt: DateTime(2026, 8, 22, 14, 30),
    );

    test('generateRepairTicketPdf generates valid 80mm PDF bytes', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'iCare Solutions',
        phone: '042-35789000',
        address: 'Plaza 4, Gulberg III, Lahore',
      );

      final bytes = await ThermalReceiptService.generateRepairTicketPdf(
        ticket: sampleTicket,
        config: config,
        advancePaid: 4000,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('generateRepairTicketPdf generates valid 58mm PDF bytes with QR code', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Mini POS Shop',
      ).copyWith(
        paperSize: '58mm',
        showBarcode: false,
        showQrCode: true,
      );

      final bytes = await ThermalReceiptService.generateRepairTicketPdf(
        ticket: sampleTicket,
        config: config,
        advancePaid: 2000,
        isDuplicate: true,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('generateTestReceiptPdf produces valid printable test receipt', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Test Lab Shop',
      );

      final bytes = await ThermalReceiptService.generateTestReceiptPdf(
        config: config,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('formatRepairTicketText contains all ticket metadata and cost details', () {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'iCare Solutions',
        phone: '042-35789000',
      );

      final text = ThermalReceiptService.formatRepairTicketText(
        ticket: sampleTicket,
        config: config,
        advancePaid: 4000,
        isDuplicate: false,
      );

      expect(text, contains('ICARE SOLUTIONS'));
      expect(text, contains('TK-2026-001'));
      expect(text, contains('Usman Ghani'));
      expect(text, contains('Apple iPhone 14 Pro Max'));
      expect(text, contains('354890102938475'));
      expect(text, contains('Battery draining fast'));
      expect(text, contains('Est. Cost: Rs 12000'));
      expect(text, contains('Advance Paid: Rs 4000'));
      expect(text, contains('Balance: Rs 8000'));
    });
  });
}
