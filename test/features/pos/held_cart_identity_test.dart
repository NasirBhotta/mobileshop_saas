import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/domain/held_cart_identity.dart';

void main() {
  group('heldCartRemoteId', () {
    test('keeps a UUID unchanged', () {
      const id = '56fe7428-dfd1-4f89-8a3a-63e686758ef1';

      expect(heldCartRemoteId(id), id);
    });

    test('maps a legacy timestamp to a stable UUID', () {
      const legacyId = '1786279189374';

      final first = heldCartRemoteId(legacyId);
      final second = heldCartRemoteId(legacyId);

      expect(first, second);
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('maps different legacy IDs to different UUIDs', () {
      expect(
        heldCartRemoteId('1786279189374'),
        isNot(heldCartRemoteId('1786279189375')),
      );
    });

    test('rejects an unknown ID format', () {
      expect(() => heldCartRemoteId('old-cart'), throwsFormatException);
    });
  });
}
