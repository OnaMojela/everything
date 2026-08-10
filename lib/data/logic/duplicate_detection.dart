import '../db/database.dart';
import 'bank_parser.dart';

/// One purchase often produces several notifications — the bank's own app, the
/// messaging app showing the bank's SMS, and caller-ID apps like Truecaller
/// that read the same SMS. They arrive within seconds of each other and
/// describe the same money movement.
///
/// These helpers decide when two reports are the same transaction.
abstract final class Dedupe {
  /// How far apart two reports of the same purchase can arrive. Apps relay the
  /// same SMS within seconds, but a bank push can lag a few minutes.
  static const window = Duration(minutes: 10);

  /// How far back to look for earlier reports of the same transaction. Wider
  /// than [window] because a message that carries the bank's own reference or
  /// timestamp identifies its transaction outright — an app that relays the
  /// same SMS a day late is still describing the same money.
  static const contentWindow = Duration(days: 7);

  /// Window used when checking a capture against transactions already saved in
  /// the ledger — wider, because the user may have typed it in earlier.
  static const ledgerWindow = Duration(hours: 6);

  /// Re-reads the text an inbox item was captured from. Everything the parser
  /// knows is derived from that text, so a stored item can always be turned
  /// back into the reading it came from.
  static ParsedNotification reparse(InboxItem item) => parseBankNotification(
        title: item.title,
        body: item.body,
        packageName: item.packageName,
      );

  /// A signature built from the facts a bank restates identically in every
  /// copy of the same message: the amount, the balance left over, the accounts
  /// involved, the payment reference and the bank's own timestamp. Two
  /// messages sharing one are the same transaction, no matter which app
  /// delivered them or how each formatted the numbers.
  ///
  /// Direction is deliberately left out. It is the one field each app words
  /// differently enough for the parser to read differently, and the reference,
  /// stamp and balance already pin the transaction down.
  static String fingerprint(ParsedNotification p) {
    if (p.amountCents == null) return '';
    final refs = p.accountRefs.map((r) => r.toString()).toList()..sort();
    return [
      'amount:${p.amountCents}',
      if (p.availableBalanceCents != null) 'balance:${p.availableBalanceCents}',
      if (refs.isNotEmpty) 'accounts:${refs.join('+')}',
      if (p.stampedAt.isNotEmpty) 'at:${p.stampedAt}',
      if (p.reference.isNotEmpty) 'ref:${p.reference.toUpperCase()}',
    ].join('|');
  }

  /// Whether a fingerprint carries enough to identify one particular
  /// transaction. An amount on its own does not — two R30 coffees in a day
  /// would collide — but a reference, a timestamp or the balance left behind
  /// pins it down.
  static bool isStrongFingerprint(ParsedNotification p) =>
      p.amountCents != null &&
      (p.reference.isNotEmpty ||
          p.stampedAt.isNotEmpty ||
          p.availableBalanceCents != null);

  /// True when [candidate] looks like another report of [existing].
  ///
  /// Messages that identify their transaction — by the bank's reference or
  /// timestamp — are compared on that alone. Everything else falls back to
  /// amount, direction and timing, with card digits vetoing a match when both
  /// sides know them and they disagree.
  /// Pass [existingReading] when the caller has already re-read [existing],
  /// so a queue-wide sweep doesn't re-parse the same text on every comparison.
  static bool isSameTransaction(
    ParsedNotification candidate,
    DateTime candidateAt,
    InboxItem existing, {
    Duration window = window,
    ParsedNotification? existingReading,
  }) {
    final existingParsed = existingReading ?? reparse(existing);
    final gap = candidateAt.difference(existing.receivedAt).abs();
    // Bank references repeat across months — "Ref: SALARY" every payday — so
    // even an exact identifier only settles things within a few days.
    if (gap <= contentWindow &&
        candidate.amountCents != null &&
        candidate.amountCents == existingParsed.amountCents) {
      // Both messages name their transaction and they name different ones:
      // two real purchases that happen to have cost the same.
      if (_identifiesADifferentTransaction(candidate, existingParsed)) {
        return false;
      }
      if (sameReference(candidate, existingParsed)) return true;
      if (stampsIdentify(candidate.stampedAt, existingParsed.stampedAt)) {
        return true;
      }
      if (isStrongFingerprint(candidate) &&
          isStrongFingerprint(existingParsed) &&
          fingerprint(candidate) == fingerprint(existingParsed)) {
        return true;
      }
    }

    if (candidate.amountCents == null || existing.amount == null) return false;
    if (candidate.amountCents != existing.amount) return false;

    final candidateType = candidate.type?.index;
    if (candidateType != null &&
        existing.txType != null &&
        candidateType != existing.txType) {
      return false;
    }

    if (gap > window) return false;

    final a = candidate.accountLast4;
    final b = existing.accountLast4;
    if (a.isNotEmpty && b.isNotEmpty && a != b) return false;

    return true;
  }

  /// The other side of the same money movement: a payment out of somebody
  /// else's account arriving alongside the user's own notification for it.
  ///
  /// When money is sent, both parties' banks can announce it on the same
  /// phone. The copy about the other person's account never mentions a
  /// balance — banks only report balances for accounts you hold — so it is
  /// recognisable, and counting it would book the same money twice.
  static bool isMirrorReport(
    ParsedNotification candidate,
    DateTime candidateAt,
    InboxItem existing,
    ParsedNotification existingParsed, {
    Duration window = window,
  }) {
    if (candidate.ownership != Ownership.someoneElse) return false;
    if (candidate.availableBalanceCents != null) return false;
    if (candidate.amountCents == null) return false;
    if (candidate.amountCents != existing.amount) return false;

    final gap = candidateAt.difference(existing.receivedAt).abs();
    if (gap > contentWindow) return false;

    // Same amount plus the bank's own identifier for the movement, or simply
    // close enough in time. Direction is deliberately ignored: the two sides
    // describe the same money going opposite ways.
    if (sameReference(candidate, existingParsed)) return true;
    if (stampsIdentify(candidate.stampedAt, existingParsed.stampedAt)) {
      return true;
    }
    return gap <= window;
  }

  /// Picks the existing item a new capture duplicates, if any. Prefers the
  /// primary (non-duplicate) item so chains never form.
  static InboxItem? findDuplicate(
    ParsedNotification candidate,
    DateTime candidateAt,
    List<InboxItem> recent, {
    Duration window = window,
  }) {
    InboxItem? fallback;
    for (final item in recent) {
      if (!isSameTransaction(candidate, candidateAt, item, window: window)) {
        continue;
      }
      if (item.duplicateOfId == null) return item;
      fallback ??= rootOf(item, recent);
    }
    return fallback;
  }

  /// Follows [item] up its duplicate chain to the report actually being kept.
  static InboxItem rootOf(InboxItem item, List<InboxItem> all) {
    var current = item;
    // Bounded by the list length so a corrupt cycle can never spin forever.
    for (var hops = 0; hops < all.length; hops++) {
      final parentId = current.duplicateOfId;
      if (parentId == null) return current;
      final parent = all.where((i) => i.id == parentId).firstOrNull;
      if (parent == null) return current;
      current = parent;
    }
    return current;
  }

  /// A transaction already in the ledger that this capture probably repeats —
  /// used to warn before saving the same purchase twice.
  static Transaction? findLedgerDuplicate(
    ParsedNotification candidate,
    DateTime candidateAt,
    List<Transaction> transactions, {
    String? accountId,
    Duration window = ledgerWindow,
  }) {
    if (candidate.amountCents == null) return null;
    for (final tx in transactions) {
      if (tx.amount != candidate.amountCents) continue;
      if (candidate.type != null && tx.txType != candidate.type!.index) continue;
      if (accountId != null && tx.accountId != accountId) continue;
      if (_within(tx, candidateAt, window)) return tx;
    }
    return null;
  }

  static bool _within(Transaction tx, DateTime at, Duration window) {
    final day = DateTime.parse(tx.day);
    final time = tx.time;
    var stamp = day;
    if (time != null && time.contains(':')) {
      final parts = time.split(':');
      stamp = DateTime(day.year, day.month, day.day,
          int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    }
    // Without a time on the transaction, treat any same-day match as close.
    if (time == null) {
      return day.year == at.year && day.month == at.month && day.day == at.day;
    }
    return stamp.difference(at).abs() <= window;
  }

  /// Adds [label] to a comma-separated "also reported by" list, skipping blanks
  /// and repeats, and keeping it short enough to display.
  static String addSource(String existing, String label) {
    final name = label.trim();
    if (name.isEmpty) return existing;
    final parts = existing
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.any((p) => p.toLowerCase() == name.toLowerCase())) return existing;
    parts.add(name);
    return parts.take(4).join(', ');
  }

  /// When several apps report the same purchase, keep the most informative
  /// one: highest parse confidence, then the one naming an account.
  static bool isBetterThan(ParsedNotification candidate, InboxItem existing) {
    if (candidate.confidence > existing.confidence + 0.05) return true;
    if (candidate.accountLast4.isNotEmpty && existing.accountLast4.isEmpty) {
      return true;
    }
    return false;
  }

  /// Which of two reports of the same transaction to keep as the one the user
  /// reviews. A report about the user's own account always wins over one about
  /// somebody else's, and a report quoting the balance wins over one that
  /// doesn't — those are the ones worth acting on.
  static bool prefers(ParsedNotification candidate, ParsedNotification existing) {
    if (candidate.ownership != existing.ownership) {
      if (candidate.ownership == Ownership.someoneElse) return false;
      if (existing.ownership == Ownership.someoneElse) return true;
    }
    final hasBalance = candidate.availableBalanceCents != null;
    final hadBalance = existing.availableBalanceCents != null;
    if (hasBalance != hadBalance) return hasBalance;
    if (candidate.confidence > existing.confidence + 0.05) return true;
    return candidate.accountLast4.isNotEmpty && existing.accountLast4.isEmpty;
  }

  /// True when both messages quote the same payment reference.
  static bool sameReference(ParsedNotification a, ParsedNotification b) =>
      a.reference.isNotEmpty &&
      a.reference.toUpperCase() == b.reference.toUpperCase();

  /// True when both messages quote an identifier and the identifiers differ.
  static bool _identifiesADifferentTransaction(
    ParsedNotification a,
    ParsedNotification b,
  ) {
    if (a.reference.isNotEmpty &&
        b.reference.isNotEmpty &&
        a.reference.toUpperCase() != b.reference.toUpperCase()) {
      return true;
    }
    return stampsConflict(a.stampedAt, b.stampedAt);
  }

  /// Bank stamps are compared slot by slot, so a copy that gives only the time
  /// and one that gives the date as well are not treated as disagreeing.
  static bool stampsConflict(String a, String b) {
    final x = _stampSlots(a);
    final y = _stampSlots(b);
    for (var i = 0; i < x.length; i++) {
      if (x[i].isNotEmpty && y[i].isNotEmpty && x[i] != y[i]) return true;
    }
    return false;
  }

  /// True when both stamps give a full date *and* time and they are the same
  /// moment. A shared time alone is not enough — two R30 coffees bought at
  /// 14:22 on different days would collide.
  static bool stampsIdentify(String a, String b) {
    final x = _stampSlots(a);
    final y = _stampSlots(b);
    if (x.any((s) => s.isEmpty) || y.any((s) => s.isEmpty)) return false;
    return x[0] == y[0] && x[1] == y[1];
  }

  static List<String> _stampSlots(String stamp) {
    final parts = stamp.split(' ');
    return [
      parts.isNotEmpty ? parts[0] : '',
      parts.length > 1 ? parts[1] : '',
    ];
  }
}
