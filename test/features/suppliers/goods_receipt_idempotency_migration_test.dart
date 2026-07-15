import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goods receipt retry is checked before fully received status', () {
    final sql =
        File(
          'supabase/migrations/20260715002000_fix_goods_receipt_retry_idempotency.sql',
        ).readAsStringSync();

    const idempotencyCheck =
        'if exists (select 1 from public.goods_receipts where id = p_receipt_id) then';
    const receivedStatusCheck = "if v_po.status = 'received' then";

    final replacementStart = sql.indexOf(r'v_new text := $fragment$');
    final replacementEnd = sql.indexOf(r'$fragment$;', replacementStart);
    final replacement = sql.substring(replacementStart, replacementEnd);

    expect(replacement.indexOf(idempotencyCheck), greaterThanOrEqualTo(0));
    expect(replacement.indexOf(receivedStatusCheck), greaterThanOrEqualTo(0));
    expect(
      replacement.indexOf(idempotencyCheck),
      lessThan(replacement.indexOf(receivedStatusCheck)),
    );
  });
}
