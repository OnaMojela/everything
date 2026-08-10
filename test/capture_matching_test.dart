import 'package:everything/core/services/notification_capture.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/logic/bank_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Account account(String id, String name, String hints) => Account(
      id: id,
      name: name,
      accountType: 0,
      colorValue: 0,
      initialBalance: 0,
      includeInNetWorth: true,
      archived: false,
      sortOrder: 0,
      notificationHints: hints,
    );

void main() {
  final cheque = account('a1', 'Cheque', '1234,fnb');
  final savings = account('a2', 'Savings', '8899');
  final capitec = account('a3', 'Capitec Daily', 'capitec');
  final accounts = [cheque, savings, capitec];

  ParsedNotification parse(String body, {String pkg = ''}) =>
      parseBankNotification(title: '', body: body, packageName: pkg);

  test('matches on card last four digits', () {
    final p = parse('Card purchase of R150 at PNP. Acc ..8899');
    expect(NotificationCaptureService.matchAccount(p, accounts)?.id, 'a2');
  });

  test('card digits win over a bank-name match', () {
    // Mentions FNB (cheque) but the digits belong to savings.
    final p = parse('FNB :-) Purchase R99 at SHELL. Acc ..8899');
    expect(NotificationCaptureService.matchAccount(p, accounts)?.id, 'a2');
  });

  test('falls back to the bank name when no digits are present', () {
    final p = parse('You spent R42 at SHELL', pkg: 'za.co.capitecbank');
    expect(NotificationCaptureService.matchAccount(p, accounts)?.id, 'a3');
  });

  test('returns null when nothing matches', () {
    final p = parse('Purchase R10 at SHOP. Acc ..0000');
    expect(NotificationCaptureService.matchAccount(p, accounts), isNull);
  });

  test('returns null when the account has no hints configured', () {
    final p = parse('Purchase R10 at SHOP. Acc ..1234');
    expect(
      NotificationCaptureService.matchAccount(p, [account('x', 'Blank', '')]),
      isNull,
    );
  });

  test('hint matching ignores case and surrounding whitespace', () {
    final messy = account('a4', 'Messy', ' FNB , 4321 ');
    final p = parse('Purchase R10 at SHOP. Acc ..4321');
    expect(NotificationCaptureService.matchAccount(p, [messy])?.id, 'a4');
  });

  group('knowing which digits are the user’s own', () {
    test('only four-digit hints count as account numbers', () {
      expect(NotificationCaptureService.ownAccountDigits(accounts),
          {'1234', '8899'});
    });

    ParsedNotification resolved(String body, {String pkg = ''}) => resolveOwnership(
          parse(body, pkg: pkg),
          NotificationCaptureService.ownAccountDigits(accounts),
        );

    test('a payee’s account number is not matched to an account of yours', () {
      // The digits belong to whoever was paid, and no balance of the user's
      // is quoted, so this movement is not theirs to record.
      final p = resolved('Capitec: R350,00 paid to a/c **7777. Ref: RENT',
          pkg: 'za.co.capitecbank');
      expect(p.ownership, Ownership.someoneElse);
      expect(NotificationCaptureService.matchAccount(p, accounts), isNull);
    });

    test('a message quoting your balance is yours, whoever was paid', () {
      final p = resolved(
          'Capitec: R350,00 paid to a/c **7777. Ref: RENT. Avail R900,00',
          pkg: 'za.co.capitecbank');
      expect(p.ownership, Ownership.someoneElse);
      expect(NotificationCaptureService.matchAccount(p, accounts)?.id, 'a3');
    });

    test('money paid into an account of yours matches that account', () {
      final p = resolved('R350,00 paid to a/c **8899. Ref: RENT. Avail R900,00');
      expect(p.ownership, Ownership.mine);
      expect(NotificationCaptureService.matchAccount(p, accounts)?.id, 'a2');
    });
  });
}
