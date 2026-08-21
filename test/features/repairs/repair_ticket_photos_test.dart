import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

void main() {
  group('RepairTicketModel Photo Paths', () {
    test('serializes and deserializes photo_paths list correctly', () {
      final now = DateTime.now();
      const photos = [
        'repairs/tenant-1/ticket-1/photo1.webp',
        'repairs/tenant-1/ticket-1/photo2.webp',
      ];

      final ticket = RepairTicketModel(
        id: 'ticket-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        ticketNo: 'REP-2026-001',
        customerName: 'Ali Raza',
        deviceBrand: 'Samsung',
        deviceModel: 'Galaxy A15',
        faultDescription: 'Broken Screen',
        status: RepairTicketStatus.received,
        photoPaths: photos,
        createdBy: 'user-1',
        createdAt: now,
        updatedAt: now,
      );

      expect(ticket.photoPaths, equals(photos));

      final map = ticket.toInsertMap();
      expect(map['photo_paths'], equals(photos));

      final fromMap = RepairTicketModel.fromMap(map);
      expect(fromMap.photoPaths, equals(photos));
      expect(fromMap.id, equals('ticket-1'));
      expect(fromMap.customerName, equals('Ali Raza'));
    });

    test('handles legacy single photo_path string correctly in fromMap', () {
      final map = <String, dynamic>{
        'id': 'ticket-legacy',
        'tenant_id': 'tenant-1',
        'branch_id': 'branch-1',
        'customer_name': 'Hamza',
        'device_brand': 'Apple',
        'device_model': 'iPhone 13',
        'fault_description': 'Battery Issue',
        'status': 'received',
        'photo_path': 'legacy/path/photo.jpg',
        'created_by': 'user-1',
      };

      final ticket = RepairTicketModel.fromMap(map);
      expect(ticket.photoPaths, equals(['legacy/path/photo.jpg']));
    });

    test('defaults to empty list when photo_paths is absent', () {
      final map = <String, dynamic>{
        'id': 'ticket-empty',
        'tenant_id': 'tenant-1',
        'branch_id': 'branch-1',
        'customer_name': 'Hamza',
        'device_brand': 'Apple',
        'device_model': 'iPhone 13',
        'fault_description': 'Battery Issue',
        'status': 'received',
        'created_by': 'user-1',
      };

      final ticket = RepairTicketModel.fromMap(map);
      expect(ticket.photoPaths, isEmpty);
    });

    test('copyWith updates photoPaths correctly', () {
      const initial = RepairTicketModel(
        id: 'ticket-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        customerName: 'Ali',
        deviceBrand: 'Xiaomi',
        deviceModel: 'Redmi 12',
        faultDescription: 'Speaker issue',
        createdBy: 'user-1',
        photoPaths: ['photo1.jpg'],
      );

      final updated = initial.copyWith(
        photoPaths: ['photo1.jpg', 'photo2.jpg'],
      );

      expect(updated.photoPaths, equals(['photo1.jpg', 'photo2.jpg']));
      expect(initial.photoPaths, equals(['photo1.jpg']));
    });
  });

  group('Repair Photo Migration and Codebase Integrity', () {
    test('database migration file exists and defines storage bucket and column', () {
      final migrationFile = File('supabase/migrations/20260822000100_repair_ticket_photos.sql');
      expect(migrationFile.existsSync(), isTrue);

      final content = migrationFile.readAsStringSync();
      expect(content, contains('photo_paths text[] not null default'));
      expect(content, contains('repair-photos'));
      expect(content, contains('repair_photos_tenant_insert'));
    });

    test('repair form screen has photo picker wiring', () {
      final formFile = File('lib/features/repairs/presentation/screens/repair_form_screen.dart');
      expect(formFile.existsSync(), isTrue);

      final content = formFile.readAsStringSync();
      expect(content, contains('_photoPaths'));
      expect(content, contains('_pickFromCamera'));
      expect(content, contains('_pickFromGallery'));
      expect(content, contains('photoPaths: _photoPaths'));
    });

    test('repairs list screen has photo badge and details gallery', () {
      final listFile = File('lib/features/repairs/presentation/screens/repairs_list_screen.dart');
      expect(listFile.existsSync(), isTrue);

      final content = listFile.readAsStringSync();
      expect(content, contains('ticket.photoPaths.isNotEmpty'));
      expect(content, contains('_CardPhotoPreview'));
      expect(content, contains('AppStrings.repairDevicePhotos'));
    });
  });
}
