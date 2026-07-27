import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dashboard ledger foundation audit', () {
    late String accountMigration;
    late String accountRepository;
    late String mobileServiceMigration;
    late String mobileServiceVoidMigration;

    setUpAll(() {
      accountMigration =
          File(
            'supabase/migrations/20260709000200_account_module.sql',
          ).readAsStringSync();
      accountRepository =
          File(
            'lib/features/accounts/data/repositories/accounts_repository.dart',
          ).readAsStringSync();
      mobileServiceMigration =
          File(
            'supabase/migrations/20260725000300_mobile_services_transactions.sql',
          ).readAsStringSync();
      mobileServiceVoidMigration =
          File(
            'supabase/migrations/20260725000400_mobile_services_void_reports.sql',
          ).readAsStringSync();
    });

    test('default cash account has one stable shop-cash identity', () {
      expect(accountRepository, contains("name: 'Cash in Shop'"));
      expect(accountRepository, contains('type: AccountType.cash'));
      expect(accountRepository, contains('isDefault: true'));
      expect(accountMigration, contains('accounts_default_per_branch'));
      expect(
        accountMigration,
        contains('where is_default = true and is_active = true'),
      );
    });

    test('generic remote account writes reuse a caller-stable UUID', () {
      expect(accountMigration, contains('on conflict (id) do nothing'));
      expect(accountMigration, contains('if v_inserted is not null then'));
      expect(accountRepository, contains("'p_transaction_id': transaction.id"));
    });

    test('account transfers use two linked legs with equal amount', () {
      expect(accountMigration, contains("'transfer_out'"));
      expect(accountMigration, contains("'transfer_in'"));
      expect(accountMigration, contains('p_transfer_group_id'));
      expect(accountRepository, contains('transferGroupId: groupId'));
      expect(
        accountRepository,
        contains("'p_out_transaction_id': outgoing.id"),
      );
      expect(accountRepository, contains("'p_in_transaction_id': incoming.id"));
    });

    test('mobile services posts both cash and wallet ledger legs', () {
      expect(mobileServiceMigration, contains('p_cash_ledger_transaction_id'));
      expect(
        mobileServiceMigration,
        contains('p_provider_ledger_transaction_id'),
      );
      expect(mobileServiceMigration, contains("'mobile_service_cash'"));
      expect(mobileServiceMigration, contains("'mobile_service_wallet'"));
      expect(
        mobileServiceMigration,
        contains('set current_balance = current_balance + v_customer_cash'),
      );
      expect(
        mobileServiceMigration,
        contains('set current_balance = current_balance - p_service_amount'),
      );
    });

    test('mobile service void is idempotent and uses reversal entries', () {
      expect(
        mobileServiceVoidMigration,
        contains("if v_transaction.status = 'voided' then"),
      );
      expect(mobileServiceVoidMigration, contains("'mobile_service_reversal'"));
      expect(
        mobileServiceVoidMigration,
        contains('insert into public.account_transactions'),
      );
      expect(mobileServiceVoidMigration, contains("set status = 'voided'"));
    });
  });
}
