import 'package:everything/data/logic/bank_parser.dart';
import 'package:everything/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedNotification parse(String body, {String title = '', String pkg = ''}) =>
    parseBankNotification(title: title, body: body, packageName: pkg);

void main() {
  group('amount parsing', () {
    test('reads plain rand amounts', () {
      expect(parse('Card purchase of R150.00 at PICK N PAY').amountCents, 15000);
    });

    test('reads comma decimal with space thousands (SA style)', () {
      expect(parse('Debit of R1 234,56 from your account').amountCents, 123456);
    });

    test('reads comma thousands with dot decimal', () {
      expect(parse('You spent R12,345.67 at MAKRO').amountCents, 1234567);
    });

    test('reads whole amounts without decimals', () {
      expect(parse('Purchase R80 at KFC').amountCents, 8000);
    });

    test('treats three trailing digits as thousands, not cents', () {
      expect(parse('Payment of R1.500 processed').amountCents, 150000);
    });

    test('handles other currencies and normalises the symbol', () {
      final usd = parse(r'Purchase of $25.50 at STARBUCKS');
      expect(usd.amountCents, 2550);
      expect(usd.currencySymbol, r'$');
      expect(parse('Debit ZAR 99.99 at SHELL').currencySymbol, 'R');
    });

    test('returns nothing when there is no money in the text', () {
      expect(parse('Your statement is ready to view').amountCents, isNull);
    });

    test('reads a four-figure amount whole', () {
      // Read left to right in three-digit groups, "R2664.68" stopped after
      // "266" and came out as R266.00.
      expect(parse('Purchase R2664.68 at MAKRO').amountCents, 266468);
      expect(parse('Purchase R2664,68 at MAKRO').amountCents, 266468);
      expect(parse('Purchase R99999.99 at MAKRO').amountCents, 9999999);
    });
  });

  group('direction', () {
    test('detects debits', () {
      expect(parse('Card purchase of R150.00 at PNP').type, TxType.expense);
      expect(parse('R250.00 debited from account ..5678').type, TxType.expense);
      expect(parse('You have spent R42.00 at SHELL').type, TxType.expense);
      expect(parse('ATM withdrawal R500 processed').type, TxType.expense);
    });

    test('detects credits', () {
      expect(parse('R5,000.00 credited to your account').type, TxType.income);
      expect(parse('Salary of R25 000,00 received').type, TxType.income);
      expect(parse('Deposit of R300 was made').type, TxType.income);
    });

    test('classifies refunds separately', () {
      expect(parse('Refund of R120.00 received from TAKEALOT').type, TxType.refund);
    });

    test('uses the first keyword when both appear', () {
      expect(parse('Refund of R50 for your purchase at GAME').type, TxType.refund);
    });
  });

  group('account hints', () {
    test('reads explicit account digits', () {
      expect(parse('R100 debited. Acc no. 1234').accountLast4, '1234');
      expect(parse('Purchase R10 with card ending 5678').accountLast4, '5678');
      expect(parse('Debit R10 from a/c: xxxx9012').accountLast4, '9012');
    });

    test('reads masked digits', () {
      expect(parse('Card purchase R99 at SHELL. Acc ..4321').accountLast4, '4321');
      expect(parse('Spent R20 on **8765').accountLast4, '8765');
    });

    test('is empty when no digits are present', () {
      expect(parse('You spent R20 at SHELL').accountLast4, '');
    });
  });

  group('merchant', () {
    test('extracts merchant after "at"', () {
      expect(parse('Card purchase of R150.00 at PICK N PAY').merchant, 'PICK N PAY');
    });

    test('strips trailing date and reference noise', () {
      expect(
        parse('Card purchase R150.00 at CHECKERS on 02 Aug. Avail R1 200').merchant,
        'CHECKERS',
      );
      expect(parse('Purchase R99 at SHELL using card 1234').merchant, 'SHELL');
    });

    test('ignores bare numbers', () {
      expect(parse('Transfer R100 to 1234567').merchant, '');
    });
  });

  group('bank identification', () {
    test('identifies the bank from the sending package', () {
      expect(parse('R10 spent', pkg: 'za.co.capitecbank').bankName, 'Capitec');
    });

    test('falls back to the message text', () {
      expect(parse('FNB :-) Card purchase of R150 at PNP').bankName, 'FNB');
      expect(parse('Std Bank: purchase of R80 at KFC').bankName, 'Standard Bank');
    });
  });

  group('available balance', () {
    test('reads the common shorthand forms', () {
      expect(
        parse('Card purchase R150.00 at PNP. Avail R3 100,00').availableBalanceCents,
        310000,
      );
      expect(
        parse('R250 debited. Available balance R4 300,00').availableBalanceCents,
        430000,
      );
      expect(parse('Purchase R20. Bal: R99.50').availableBalanceCents, 9950);
      expect(
        parse('Payment R80 sent. New balance R1,234.56').availableBalanceCents,
        123456,
      );
      expect(
        parse('Debit R10. Current balance is R500.00').availableBalanceCents,
        50000,
      );
    });

    test('never mistakes the balance for the transaction amount', () {
      final r = parse('Card purchase of R249,99 at WOOLWORTHS. Avail R3 100,00');
      expect(r.amountCents, 24999);
      expect(r.availableBalanceCents, 310000);
    });

    test('finds the amount even when the balance is written first', () {
      final r = parse('Available balance R4 300,00 after purchase of R150,00');
      expect(r.amountCents, 15000);
      expect(r.availableBalanceCents, 430000);
    });

    test('is null when the message has no balance', () {
      expect(parse('Card purchase R150.00 at PNP').availableBalanceCents, isNull);
    });

    test('is not reported for balance-only notices', () {
      // These are rejected as noise, so nothing should be applied from them.
      expect(parse('Your available balance is R2 500.00').isTransaction, isFalse);
      expect(parse('Your available balance is R2 500.00').availableBalanceCents,
          isNull);
    });

    test('reads available credit wording too', () {
      expect(
        parse('Purchase R100 on your card. Available credit R7 500,00')
            .availableBalanceCents,
        750000,
      );
    });

    test('reads a four-figure balance whole', () {
      // The bug behind "Bank reports balance R266.00" on a message that said
      // "Avail R2664.68".
      expect(
        parse('R350.00 paid to a/c **8754. Avail R2664.68').availableBalanceCents,
        266468,
      );
      expect(
        parse('R350,00 paid to a/c **8754. Avail R2664,68').availableBalanceCents,
        266468,
      );
    });
  });

  group('which account the money moved on', () {
    test('keeps the direction word that introduced the digits', () {
      expect(
        parse('R350,00 paid to a/c **8754. Avail R2664,68').accountRefs,
        [const AccountRef('8754', AccountRole.destination)],
      );
    });

    test('reads both sides of a transfer', () {
      expect(
        parse('R500,00 paid from a/c **1111 to a/c **2222').accountRefs,
        [
          const AccountRef('1111', AccountRole.source),
          const AccountRef('2222', AccountRole.destination),
        ],
      );
    });

    test('leaves the role open when the message only names an account', () {
      expect(
        parse('Card purchase R99 at SHELL. Acc ..4321').accountRefs,
        [const AccountRef('4321', AccountRole.unspecified)],
      );
    });

    test('is empty when no account is named', () {
      expect(parse('You spent R20 at SHELL').accountRefs, isEmpty);
      expect(parse('Transfer R100 to 1234567').accountRefs, isEmpty);
    });
  });

  group('the bank’s own reference and timestamp', () {
    test('reads the payment reference', () {
      expect(
        parse('R350,00 paid to a/c **8754. Ref: KEIRA TICKET. Avail R100').reference,
        'KEIRA TICKET',
      );
      expect(parse('R100 received. Reference SALARY AUG').reference, 'SALARY AUG');
      expect(parse('R10 paid, ref no. INV-00912, thanks').reference, 'INV-00912');
    });

    test('normalises the timestamp however the app wrote it', () {
      final iso = parse(
          'R350.00 paid to a/c **8754. Ref: KEIRA TICKET. 2026-08-04 02:03. Avail R2664.68');
      final worded = parse(
          'Nedbank: Transaction. R350,00 paid to a/c **8754. Ref: KEIRA TICKET. '
          '04 Aug 26 at 02:03. Avail R2664,68.');
      expect(iso.stampedAt, '08-04 02:03');
      expect(worded.stampedAt, iso.stampedAt);
    });

    test('keeps whichever half the message gave', () {
      expect(parse('Purchase R99 at PNP on 02 Aug. Avail R10').stampedAt, '08-02 ');
      expect(parse('Purchase R99 at PNP at 13:45').stampedAt, ' 13:45');
      expect(parse('Purchase R99 at PNP').stampedAt, '');
    });
  });

  group('whose account the message is about', () {
    // Nedbank's wording for an EFT: the digits belong to whoever was paid.
    const nedbank =
        'R350,00 paid to a/c **8754. Ref: KEIRA TICKET. 04 Aug 26 at 02:03. Avail R2664,68';

    ParsedNotification resolve(String body, Set<String> own) =>
        resolveOwnership(parse(body), own);

    test('digits that are not yours stay the other party’s', () {
      final r = resolve(nedbank, {'1234'});
      expect(r.ownership, Ownership.someoneElse);
      expect(r.accountLast4, '');
      expect(r.counterpartyLast4, '8754');
      expect(r.matchHints, isNot(contains('8754')));
      expect(r.type, TxType.expense);
    });

    test('money paid to an account of yours is money arriving', () {
      final r = resolve(nedbank, {'8754'});
      expect(r.ownership, Ownership.mine);
      expect(r.accountLast4, '8754');
      expect(r.type, TxType.income);
    });

    test('money paid out of an account of yours is an expense', () {
      final r = resolve('R500,00 paid from a/c **1111 to a/c **2222', {'1111'});
      expect(r.type, TxType.expense);
      expect(r.accountLast4, '1111');
      expect(r.counterpartyLast4, '2222');
    });

    test('your account is found on whichever side of a transfer it sits', () {
      final r = resolve('R500,00 paid from a/c **1111 to a/c **2222', {'2222'});
      expect(r.accountLast4, '2222');
      expect(r.counterpartyLast4, '1111');
      expect(r.type, TxType.income);
    });

    test('an account named with no direction keeps the keyword reading', () {
      final r = resolve('Card purchase R99 at SHELL. Acc ..4321', {'4321'});
      expect(r.ownership, Ownership.mine);
      expect(r.type, TxType.expense);
    });

    test('nothing is decided until you have said which digits are yours', () {
      final r = resolve(nedbank, const {});
      expect(r.ownership, Ownership.unknown);
      expect(r.accountLast4, '8754');
    });
  });

  group('noise rejection', () {
    test('ignores balance notices, OTPs and marketing', () {
      for (final text in [
        'Your available balance is R2 500.00',
        'Your OTP is 123456. Do not share it. R0.00',
        'Save up to R500 on your next purchase at GAME',
        'Get a loan offer of R50 000 today',
      ]) {
        expect(parse(text).isTransaction, isFalse, reason: text);
      }
    });

    test('ignores declined payments', () {
      expect(parse('Card purchase of R150 at PNP has been declined').isTransaction,
          isFalse);
    });
  });

  group('end to end', () {
    test('parses a full FNB notification', () {
      final r = parse(
        'FNB :-) Card purchase of R249,99 at WOOLWORTHS on 02 Aug. Acc ..1234. Avail R3 100,00',
        title: 'FNB',
        pkg: 'za.co.fnb.connect.itt',
      );
      expect(r.isTransaction, isTrue);
      expect(r.amountCents, 24999);
      expect(r.type, TxType.expense);
      expect(r.merchant, 'WOOLWORTHS');
      expect(r.accountLast4, '1234');
      expect(r.bankName, 'FNB');
      expect(r.confidence, greaterThan(0.8));
      expect(r.matchHints, contains('1234'));
    });

    test('parses a Capitec credit', () {
      final r = parse(
        'Capitec: R7 500,00 credited to account ..8899. Available R9 000,00',
        pkg: 'za.co.capitecbank',
      );
      expect(r.isTransaction, isTrue);
      expect(r.amountCents, 750000);
      expect(r.type, TxType.income);
      expect(r.accountLast4, '8899');
    });

    test('an unparseable message is not a transaction', () {
      expect(parse('Hello there').isTransaction, isFalse);
    });
  });
}
