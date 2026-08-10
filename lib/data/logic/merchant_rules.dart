import '../db/database.dart';

/// Bank messages name the same shop inconsistently — "PICK N PAY CRN 4471",
/// "PicknPay Sandton", "PICK N PAY*1234". These helpers reduce those to a
/// stable key so a category learned once keeps applying.
abstract final class MerchantMatching {
  /// Fragments banks append that say nothing about which shop it was.
  static const _noiseTokens = {
    'pty', 'ltd', 'inc', 'cc', 'sa', 'za', 'store', 'stores', 'branch', 'crn',
    'ref', 'card', 'pos', 'atm', 'tel', 'www', 'com', 'co',
  };

  /// Lowercased, punctuation-free, number-free, noise-free merchant name.
  /// Returns an empty string when nothing meaningful is left.
  static String key(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';

    final tokens = cleaned
        .split(' ')
        .where((t) => t.isNotEmpty)
        // Drop store/branch numbers and other pure digits.
        .where((t) => !RegExp(r'^\d+$').hasMatch(t))
        .where((t) => !_noiseTokens.contains(t))
        .toList();
    if (tokens.isEmpty) return '';
    // Four tokens is plenty to identify a merchant.
    return tokens.take(4).join(' ');
  }

  /// The first meaningful word — used to match different branches of one shop.
  static String stem(String raw) {
    final k = key(raw);
    if (k.isEmpty) return '';
    return k.split(' ').first;
  }

  /// Finds the rule that should categorise [merchant].
  ///
  /// Exact key first; failing that, the highest-scoring rule sharing a first
  /// word at least four characters long, so "WOOLWORTHS SANDTON" still matches
  /// a rule learned from "WOOLWORTHS ROSEBANK".
  static MerchantRule? bestMatch(String merchant, List<MerchantRule> rules) {
    final k = key(merchant);
    if (k.isEmpty || rules.isEmpty) return null;

    for (final rule in rules) {
      if (rule.merchantKey == k) return rule;
    }

    final s = stem(merchant);
    if (s.length < 4) return null;
    MerchantRule? best;
    for (final rule in rules) {
      if (rule.merchantKey.split(' ').first != s) continue;
      if (best == null || rule.hits > best.hits) best = rule;
    }
    return best;
  }
}
