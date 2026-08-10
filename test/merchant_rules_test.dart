import 'package:everything/data/db/database.dart';
import 'package:everything/data/logic/merchant_rules.dart';
import 'package:flutter_test/flutter_test.dart';

MerchantRule rule(String key, String categoryId, {int hits = 1}) => MerchantRule(
      merchantKey: key,
      displayName: key,
      categoryId: categoryId,
      hits: hits,
      updatedAt: DateTime(2026, 8, 3),
    );

void main() {
  group('merchant key', () {
    test('normalises case, punctuation and spacing', () {
      expect(MerchantMatching.key('PICK N PAY'), 'pick n pay');
      expect(MerchantMatching.key('  Pick  N   Pay '), 'pick n pay');
      expect(MerchantMatching.key('PICK-N-PAY'), 'pick n pay');
    });

    test('drops store numbers and reference digits', () {
      expect(MerchantMatching.key('PICK N PAY 4471'), 'pick n pay');
      expect(MerchantMatching.key('SHELL*1234'), 'shell');
    });

    test('drops company-suffix noise', () {
      expect(MerchantMatching.key('ACME STORES PTY LTD'), 'acme');
      expect(MerchantMatching.key('TAKEALOT CO ZA'), 'takealot');
    });

    test('is empty when nothing meaningful remains', () {
      expect(MerchantMatching.key(''), '');
      expect(MerchantMatching.key('  '), '');
      expect(MerchantMatching.key('12345'), '');
      expect(MerchantMatching.key('***'), '');
    });

    test('caps very long names', () {
      expect(
        MerchantMatching.key('ONE TWO THREE FOUR FIVE SIX'),
        'one two three four',
      );
    });
  });

  group('matching a rule', () {
    final rules = [
      rule('woolworths rosebank', 'cat_groceries', hits: 3),
      rule('shell', 'cat_transport', hits: 5),
      rule('woolworths cafe', 'cat_eating_out', hits: 1),
    ];

    test('matches the exact merchant', () {
      expect(
        MerchantMatching.bestMatch('Woolworths Rosebank', rules)?.categoryId,
        'cat_groceries',
      );
    });

    test('matches a different branch of the same shop', () {
      // Never seen "Sandton" before, but "woolworths" is known.
      expect(
        MerchantMatching.bestMatch('WOOLWORTHS SANDTON', rules)?.categoryId,
        'cat_groceries',
      );
    });

    test('prefers the more frequently confirmed rule on a stem tie', () {
      final tied = [
        rule('woolworths a', 'cat_a', hits: 2),
        rule('woolworths b', 'cat_b', hits: 9),
      ];
      expect(
        MerchantMatching.bestMatch('WOOLWORTHS ANYWHERE', tied)?.categoryId,
        'cat_b',
      );
    });

    test('ignores store numbers when matching', () {
      expect(
        MerchantMatching.bestMatch('SHELL 8891', rules)?.categoryId,
        'cat_transport',
      );
    });

    test('returns nothing for an unknown merchant', () {
      expect(MerchantMatching.bestMatch('SOME NEW SHOP', rules), isNull);
    });

    test('returns nothing for an empty merchant or no rules', () {
      expect(MerchantMatching.bestMatch('', rules), isNull);
      expect(MerchantMatching.bestMatch('SHELL', const []), isNull);
    });

    test('does not stem-match on very short words', () {
      // "BP" is too short to safely match other merchants starting with it.
      final short = [rule('bp garage', 'cat_transport')];
      expect(MerchantMatching.bestMatch('BP SOMETHING ELSE', short), isNull);
    });
  });
}
