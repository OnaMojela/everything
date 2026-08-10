import 'package:everything/data/db/database.dart';
import 'package:everything/data/logic/bank_parser.dart';
import 'package:everything/data/logic/duplicate_detection.dart';
import 'package:everything/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

final base = DateTime(2026, 8, 3, 14, 30);

InboxItem item({
  required String id,
  required int amount,
  int? txType = 0,
  String last4 = '',
  String appLabel = '',
  String body = '',
  DateTime? at,
  double confidence = 0.8,
  String? duplicateOfId,
  String alsoSeenFrom = '',
  String merchant = '',
  String bankName = '',
}) =>
    InboxItem(
      id: id,
      packageName: 'pkg.$id',
      appLabel: appLabel,
      title: '',
      body: body,
      receivedAt: at ?? base,
      amount: amount,
      txType: txType,
      merchant: merchant,
      accountLast4: last4,
      bankName: bankName,
      confidence: confidence,
      status: InboxStatus.pending.index,
      duplicateOfId: duplicateOfId,
      alsoSeenFrom: alsoSeenFrom,
    );

/// Reads a real notification body, the way the capture service does.
ParsedNotification read(String body) =>
    parseBankNotification(title: '', body: body, packageName: '');

ParsedNotification parsed({
  int amount = 15000,
  TxType? type = TxType.expense,
  String last4 = '',
  double confidence = 0.8,
}) =>
    ParsedNotification(
      amountCents: amount,
      type: type,
      accountLast4: last4,
      confidence: confidence,
    );

void main() {
  // The message from the screenshot that started all this, as the bank's own
  // push and as the SMS the messaging and caller-ID apps relay. Same money,
  // three different renderings of it.
  const bankPush = 'R350.00 paid to a/c **8754. Ref: KEIRA TICKET. '
      '2026-08-04 02:03. Avail R2664.68. Call 0800555111 for help';
  const nedbankSms = 'Nedbank: Transaction.  R350,00 paid to a/c **8754.  '
      'Ref: KEIRA TICKET.  04 Aug 26 at 02:03.  Avail R2664,68.  '
      'Call 0800555111 for help';

  group('the same message written differently', () {
    test('every copy fingerprints identically', () {
      expect(Dedupe.fingerprint(read(nedbankSms)), Dedupe.fingerprint(read(bankPush)));
      expect(Dedupe.isStrongFingerprint(read(bankPush)), isTrue);
    });

    test('a copy arriving seconds later is the same transaction', () {
      final existing = item(id: 'push', amount: 35000, body: bankPush, at: base);
      expect(
        Dedupe.isSameTransaction(
            read(nedbankSms), base.add(const Duration(seconds: 7)), existing),
        isTrue,
      );
    });

    test('a copy relayed hours later is still the same transaction', () {
      // Outside the ten-minute window, but the bank's reference and timestamp
      // say outright which transaction it is.
      final existing = item(id: 'push', amount: 35000, body: bankPush, at: base);
      expect(
        Dedupe.isSameTransaction(
            read(nedbankSms), base.add(const Duration(hours: 6)), existing),
        isTrue,
      );
    });

    test('a hundred copies all collapse onto the first', () {
      final kept = [item(id: 'first', amount: 35000, body: bankPush, at: base)];
      for (var i = 1; i <= 100; i++) {
        final found = Dedupe.findDuplicate(
            read(nedbankSms), base.add(Duration(minutes: i)), kept);
        expect(found?.id, 'first', reason: 'copy $i');
      }
    });

    test('two purchases of the same amount are told apart by their reference',
        () {
      final first = item(
        id: 'coffee1',
        amount: 3000,
        body: 'R30,00 paid to a/c **8754. Ref: COFFEE ONE. '
            '04 Aug 26 at 08:10. Avail R900,00',
        at: base,
      );
      final second = read('R30,00 paid to a/c **8754. Ref: COFFEE TWO. '
          '04 Aug 26 at 08:14. Avail R870,00');
      expect(
        Dedupe.isSameTransaction(
            second, base.add(const Duration(minutes: 4)), first),
        isFalse,
      );
    });

    test('a repeat a fortnight later is a new transaction, reference or not',
        () {
      final existing = item(id: 'push', amount: 35000, body: bankPush, at: base);
      expect(
        Dedupe.isSameTransaction(
            read(nedbankSms), base.add(const Duration(days: 14)), existing),
        isFalse,
      );
    });
  });

  group('the other party’s copy of the same payment', () {
    // Money arriving: the user's bank names the account it landed in and
    // quotes the balance; the sender's bank names their account and doesn't.
    final mine = item(
      id: 'mine',
      amount: 35000,
      body: 'R350,00 paid to a/c **8754. Ref: KEIRA TICKET. '
          '04 Aug 26 at 02:03. Avail R2664,68',
      at: base,
    );
    final theirs = resolveOwnership(
      read('R350,00 paid from a/c **1111. Ref: KEIRA TICKET. 04 Aug 26 at 02:03'),
      {'8754'},
    );

    test('is recognised as somebody else’s account', () {
      expect(theirs.ownership, Ownership.someoneElse);
      expect(theirs.availableBalanceCents, isNull);
    });

    test('is folded away rather than counted as a second transaction', () {
      expect(
        Dedupe.isMirrorReport(theirs, base, mine, Dedupe.reparse(mine)),
        isTrue,
      );
    });

    test('a report about an account of yours is never a mirror', () {
      final alsoMine = resolveOwnership(read(bankPush), {'8754'});
      expect(
        Dedupe.isMirrorReport(alsoMine, base, mine, Dedupe.reparse(mine)),
        isFalse,
      );
    });

    test('the report about your own account is the one kept', () {
      expect(Dedupe.prefers(theirs, Dedupe.reparse(mine)), isFalse);
      expect(Dedupe.prefers(resolveOwnership(read(bankPush), {'8754'}), theirs),
          isTrue);
    });
  });

  group('one purchase reported by several apps', () {
    // The real case: buying something produces a Nedbank push, the same text
    // via the messaging app, and Truecaller reading that SMS.
    final nedbank = item(
        id: 'nedbank', amount: 15000, last4: '1234', appLabel: 'Nedbank', at: base);

    test('the messaging app copy is recognised as the same transaction', () {
      final fromMessages = parsed(amount: 15000, last4: '1234');
      expect(
        Dedupe.isSameTransaction(
            fromMessages, base.add(const Duration(seconds: 4)), nedbank),
        isTrue,
      );
    });

    test('Truecaller reading the same SMS is recognised too', () {
      final fromTruecaller = parsed(amount: 15000, last4: '1234');
      expect(
        Dedupe.isSameTransaction(
            fromTruecaller, base.add(const Duration(seconds: 9)), nedbank),
        isTrue,
      );
    });

    test('a report with no card digits still matches on amount and timing', () {
      expect(
        Dedupe.isSameTransaction(
            parsed(amount: 15000), base.add(const Duration(seconds: 5)), nedbank),
        isTrue,
      );
    });

    test('all three collapse onto the first item', () {
      final existing = [nedbank];
      final found = Dedupe.findDuplicate(
          parsed(amount: 15000, last4: '1234'),
          base.add(const Duration(seconds: 6)),
          existing);
      expect(found?.id, 'nedbank');
    });

    test('duplicates point at the original, never at another duplicate', () {
      final messages = item(
        id: 'messages',
        amount: 15000,
        last4: '1234',
        at: base.add(const Duration(seconds: 4)),
        duplicateOfId: 'nedbank',
      );
      final found = Dedupe.findDuplicate(
        parsed(amount: 15000, last4: '1234'),
        base.add(const Duration(seconds: 9)),
        [messages, nedbank], // duplicate listed first on purpose
      );
      expect(found?.id, 'nedbank');
    });
  });

  group('things that are NOT duplicates', () {
    final existing = item(id: 'a', amount: 15000, last4: '1234');

    test('a different amount', () {
      expect(
        Dedupe.isSameTransaction(parsed(amount: 15001), base, existing),
        isFalse,
      );
    });

    test('money going the other way', () {
      expect(
        Dedupe.isSameTransaction(
            parsed(amount: 15000, type: TxType.income), base, existing),
        isFalse,
      );
    });

    test('the same amount on a different card', () {
      expect(
        Dedupe.isSameTransaction(parsed(amount: 15000, last4: '9999'), base, existing),
        isFalse,
      );
    });

    test('the same amount much later in the day', () {
      expect(
        Dedupe.isSameTransaction(
            parsed(amount: 15000, last4: '1234'),
            base.add(const Duration(hours: 3)),
            existing),
        isFalse,
      );
    });

    test('just outside the window', () {
      expect(
        Dedupe.isSameTransaction(parsed(amount: 15000),
            base.add(const Duration(minutes: 11)), existing),
        isFalse,
      );
    });

    test('an earlier report is matched as well as a later one', () {
      expect(
        Dedupe.isSameTransaction(
            parsed(amount: 15000), base.subtract(const Duration(minutes: 2)), existing),
        isTrue,
      );
    });
  });

  group('already in the ledger', () {
    Transaction tx({
      required int amount,
      String day = '2026-08-03',
      String? time = '14:31',
      int type = 0,
      String accountId = 'acc1',
    }) =>
        Transaction(
          id: 't1',
          txType: type,
          amount: amount,
          accountId: accountId,
          merchant: '',
          description: '',
          note: '',
          tags: '',
          day: day,
          time: time,
          createdAt: base,
        );

    test('flags a transaction saved minutes earlier', () {
      final match = Dedupe.findLedgerDuplicate(
          parsed(amount: 15000), base, [tx(amount: 15000)]);
      expect(match, isNotNull);
    });

    test('flags a same-day transaction that has no time recorded', () {
      final match = Dedupe.findLedgerDuplicate(
          parsed(amount: 15000), base, [tx(amount: 15000, time: null)]);
      expect(match, isNotNull);
    });

    test('ignores a different account when one is specified', () {
      final match = Dedupe.findLedgerDuplicate(
        parsed(amount: 15000),
        base,
        [tx(amount: 15000, accountId: 'other')],
        accountId: 'acc1',
      );
      expect(match, isNull);
    });

    test('ignores a different day', () {
      final match = Dedupe.findLedgerDuplicate(
          parsed(amount: 15000), base, [tx(amount: 15000, day: '2026-07-30')]);
      expect(match, isNull);
    });
  });

  group('recording which apps reported it', () {
    test('builds a readable list', () {
      var s = Dedupe.addSource('', 'Nedbank');
      s = Dedupe.addSource(s, 'Messages');
      s = Dedupe.addSource(s, 'Truecaller');
      expect(s, 'Nedbank, Messages, Truecaller');
    });

    test('never repeats an app or adds blanks', () {
      var s = Dedupe.addSource('Nedbank', 'nedbank');
      s = Dedupe.addSource(s, '   ');
      expect(s, 'Nedbank');
    });

    test('caps the list so it stays displayable', () {
      var s = '';
      for (final app in ['A', 'B', 'C', 'D', 'E', 'F']) {
        s = Dedupe.addSource(s, app);
      }
      expect(s.split(',').length, 4);
    });
  });

  group('keeping the most informative report', () {
    test('prefers a clearly higher confidence', () {
      final existing = item(id: 'a', amount: 100, confidence: 0.6);
      expect(Dedupe.isBetterThan(parsed(confidence: 0.9), existing), isTrue);
    });

    test('prefers the report that knows the card digits', () {
      final existing = item(id: 'a', amount: 100, confidence: 0.8);
      expect(
        Dedupe.isBetterThan(parsed(last4: '1234', confidence: 0.8), existing),
        isTrue,
      );
    });

    test('does not churn on a negligible difference', () {
      final existing = item(id: 'a', amount: 100, confidence: 0.8);
      expect(Dedupe.isBetterThan(parsed(confidence: 0.82), existing), isFalse);
    });
  });
}
