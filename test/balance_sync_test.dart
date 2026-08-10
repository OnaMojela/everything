import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/logic/domain_logic.dart';
import 'package:everything/data/models/enums.dart';
import 'package:everything/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('reconciliation maths', () {
    test('starting balance absorbs the difference', () {
      // Bank says R500 and transactions net to −R200, so we must have started
      // with R700 for the two to agree.
      expect(
        reconciledInitialBalance(reportedBalanceCents: 50000, deltaCents: -20000),
        70000,
      );
    });

    test('works with no transactions at all', () {
      expect(
        reconciledInitialBalance(reportedBalanceCents: 50000, deltaCents: 0),
        50000,
      );
    });

    test('handles a negative reported balance', () {
      expect(
        reconciledInitialBalance(reportedBalanceCents: -5000, deltaCents: -20000),
        15000,
      );
    });
  });

  group('which accounts may be synced', () {
    Account account(AccountType type) => Account(
          id: 'a',
          name: 'x',
          accountType: type.index,
          colorValue: 0,
          initialBalance: 0,
          includeInNetWorth: true,
          archived: false,
          sortOrder: 0,
          notificationHints: '',
        );

    test('everyday accounts are synced', () {
      for (final t in [
        AccountType.checking,
        AccountType.savings,
        AccountType.cash,
        AccountType.custom
      ]) {
        expect(balanceSyncSuitable(account(t)), isTrue, reason: t.label);
      }
    });

    test('credit, loan, investment and crypto are not', () {
      // "Available balance" on these means available credit or fluctuating
      // market value — not the account balance.
      for (final t in [
        AccountType.creditCard,
        AccountType.loan,
        AccountType.investment,
        AccountType.crypto
      ]) {
        expect(balanceSyncSuitable(account(t)), isFalse, reason: t.label);
      }
    });
  });

  group('syncing against a real database', () {
    late AppDatabase db;
    late Repo repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = Repo(db);
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: 'acc1',
            name: 'Cheque',
            accountType: AccountType.checking.index,
            colorValue: 0,
            initialBalance: const Value(100000), // R1000 to start
          ));
    });

    tearDown(() async => db.close());

    Future<void> spend(int cents, {String id = 'tx'}) =>
        db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: id,
              txType: TxType.expense.index,
              amount: cents,
              accountId: 'acc1',
              day: '2026-08-03',
              createdAt: DateTime(2026, 8, 3),
            ));

    Future<int> balance() async {
      final account =
          await (db.select(db.accounts)..where((a) => a.id.equals('acc1'))).getSingle();
      final txs = await db.select(db.transactions).get();
      return account.initialBalance + (accountDeltas(txs)['acc1'] ?? 0);
    }

    test('after syncing, the shown balance equals the bank figure', () async {
      await spend(15000); // R150 spent -> app thinks R850
      expect(await balance(), 85000);

      // Bank says R840 — we were R10 out (a fee we never recorded).
      final correction = await repo.syncAccountBalance('acc1', 84000);

      expect(correction, -1000);
      expect(await balance(), 84000);
    });

    test('does nothing when the balance already agrees', () async {
      await spend(15000);
      final correction = await repo.syncAccountBalance('acc1', 85000);
      expect(correction, 0);
      expect(await balance(), 85000);
    });

    test('transactions are never altered, only the starting balance', () async {
      await spend(15000, id: 'tx1');
      await spend(2500, id: 'tx2');
      await repo.syncAccountBalance('acc1', 50000);

      final txs = await db.select(db.transactions).get();
      expect(txs.map((t) => t.amount).toList()..sort(), [2500, 15000]);
      expect(await balance(), 50000);
    });

    test('a later transaction moves the balance on from the synced figure',
        () async {
      await spend(15000, id: 'tx1');
      await repo.syncAccountBalance('acc1', 84000);

      await spend(4000, id: 'tx2');
      expect(await balance(), 80000);
    });

    test('syncing repeatedly is stable', () async {
      await spend(15000);
      await repo.syncAccountBalance('acc1', 84000);
      final second = await repo.syncAccountBalance('acc1', 84000);
      expect(second, 0);
      expect(await balance(), 84000);
    });

    test('an unknown account is ignored', () async {
      expect(await repo.syncAccountBalance('nope', 1000), 0);
    });
  });
}
