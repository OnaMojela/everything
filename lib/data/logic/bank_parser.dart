import '../models/enums.dart';

/// Which side of a money movement an account number sits on.
///
/// "R350,00 paid to a/c ••8754" names the account that *received* the money;
/// whether that is the user's own account decides whether this is income or
/// an expense, so the wording around the digits has to be kept.
enum AccountRole {
  /// "paid to", "credited to", "transferred into" — the receiving account.
  destination,

  /// "paid from", "debited from", "withdrawn from" — the paying account.
  source,

  /// "Acc ••1234", "card ending 5678" — the account the message is about.
  unspecified,
}

/// An account number found in a message, with the role its wording gave it.
class AccountRef {
  final String last4;
  final AccountRole role;

  const AccountRef(this.last4, this.role);

  @override
  bool operator ==(Object other) =>
      other is AccountRef && other.last4 == last4 && other.role == role;

  @override
  int get hashCode => Object.hash(last4, role);

  @override
  String toString() => '$last4@${role.name}';
}

/// Whose account a notification is about, once the numbers in it have been
/// checked against the accounts the user actually owns.
enum Ownership {
  /// Nothing to check against — no digits in the message, or the user hasn't
  /// told us their own account numbers yet.
  unknown,

  /// One of the numbers in the message is the user's.
  mine,

  /// Numbers were named and none of them are the user's. Money moving on
  /// somebody else's account is not the user's transaction.
  someoneElse,
}

/// What a bank notification told us. [amountCents] is null when the text
/// didn't look like a transaction at all.
class ParsedNotification {
  final int? amountCents;
  final String currencySymbol;
  final TxType? type;
  final String merchant;

  /// The balance the bank reported after this transaction, when the message
  /// includes one ("Avail R3 100,00", "Available balance R4 300,00").
  final int? availableBalanceCents;

  /// Last four digits of the user's own card/account, as far as we can tell.
  /// Empty once [ownership] is [Ownership.someoneElse] — those digits belong
  /// to the other party and must never be matched to one of the user's
  /// accounts.
  final String accountLast4;

  /// Digits of the account on the other side of the movement, when the
  /// message names one that is not the user's.
  final String counterpartyLast4;

  /// Every account number the message mentioned, with its role, in the order
  /// they appear.
  final List<AccountRef> accountRefs;

  /// Bank name inferred from the sending app or the text ("FNB", "Capitec"…).
  final String bankName;

  /// The payment reference the message quoted ("Ref: KEIRA TICKET").
  final String reference;

  /// The time the *bank* stamped on the transaction, canonicalised to
  /// "MM-DD HH:mm" with either half left blank when the message omitted it.
  /// Every copy of the same message carries the same stamp however
  /// differently each app formatted it, which is what makes repeats
  /// recognisable long after the fact.
  final String stampedAt;

  /// Whose account this message is about. Only meaningful after
  /// [resolveOwnership] has compared it against the user's own numbers.
  final Ownership ownership;

  /// Rough 0..1 confidence that this is a real transaction we parsed correctly.
  final double confidence;

  const ParsedNotification({
    this.amountCents,
    this.currencySymbol = '',
    this.type,
    this.merchant = '',
    this.availableBalanceCents,
    this.accountLast4 = '',
    this.counterpartyLast4 = '',
    this.accountRefs = const [],
    this.bankName = '',
    this.reference = '',
    this.stampedAt = '',
    this.ownership = Ownership.unknown,
    this.confidence = 0,
  });

  bool get isTransaction => amountCents != null && amountCents! > 0 && type != null;

  /// Hints used to match this against a user's account. Only the user's own
  /// digits are offered — a beneficiary's account number is not a hint.
  List<String> get matchHints => [
        if (accountLast4.isNotEmpty) accountLast4,
        if (bankName.isNotEmpty) bankName.toLowerCase(),
      ];

  ParsedNotification copyWith({
    TxType? type,
    String? accountLast4,
    String? counterpartyLast4,
    Ownership? ownership,
    double? confidence,
  }) =>
      ParsedNotification(
        amountCents: amountCents,
        currencySymbol: currencySymbol,
        type: type ?? this.type,
        merchant: merchant,
        availableBalanceCents: availableBalanceCents,
        accountLast4: accountLast4 ?? this.accountLast4,
        counterpartyLast4: counterpartyLast4 ?? this.counterpartyLast4,
        accountRefs: accountRefs,
        bankName: bankName,
        reference: reference,
        stampedAt: stampedAt,
        ownership: ownership ?? this.ownership,
        confidence: confidence ?? this.confidence,
      );
}

/// Words that tell us money left the account.
const _debitWords = [
  'purchase', 'spent', 'paid', 'payment', 'debited', 'debit', 'withdrawal',
  'withdrew', 'sent', 'transfer to', 'bought', 'charged', 'deducted',
  'card swipe', 'pos ', 'atm ',
];

/// Words that tell us money arrived.
const _creditWords = [
  'received', 'credited', 'credit', 'deposit', 'deposited', 'refund',
  'refunded', 'salary', 'transfer from', 'reversal', 'cashback', 'paid in',
];

/// Notifications that mention money but are never transactions.
const _noiseWords = [
  'available balance is', 'balance enquiry', 'statement is ready', 'otp',
  'one time pin', 'one-time pin', 'do not share', 'offer', 'discount',
  'save up to', 'voucher', 'promo', 'win ', 'apply now', 'loan offer',
  'insurance quote', 'due on', 'minimum payment due', 'has been declined',
  'declined', 'failed', 'insufficient funds',
];

/// Known bank apps → display name. Used to label items and match accounts.
const bankPackages = <String, String>{
  'za.co.fnb.connect.itt': 'FNB',
  'com.fnb.connect': 'FNB',
  'za.co.capitecbank': 'Capitec',
  'com.capitec.bank': 'Capitec',
  'com.absa.mobile': 'Absa',
  'za.co.absa.banking': 'Absa',
  'com.nedbank.money': 'Nedbank',
  'za.co.nedbank': 'Nedbank',
  'com.standardbank.mobile': 'Standard Bank',
  'za.co.standardbank.mobilebanking': 'Standard Bank',
  'com.tymebank.app': 'TymeBank',
  'com.discovery.bank': 'Discovery Bank',
  'com.investec.bank': 'Investec',
  'com.africanbank.app': 'African Bank',
  'com.paypal.android.p2pmobile': 'PayPal',
  'com.google.android.apps.walletnfcrel': 'Google Wallet',
  'com.revolut.revolut': 'Revolut',
  'com.monzo.app': 'Monzo',
  'com.chase.sig.android': 'Chase',
  'com.google.android.apps.messaging': 'SMS',
  'com.samsung.android.messaging': 'SMS',
};

/// Bank names detectable from the message body itself.
const _bankNamesInText = [
  'fnb', 'capitec', 'absa', 'nedbank', 'standard bank', 'std bank', 'tymebank',
  'tyme', 'discovery bank', 'investec', 'african bank', 'paypal', 'revolut',
  'monzo', 'chase',
];


// A money figure in either "1 234,56" or "1,234.56" style, with ordinary,
// non-breaking and narrow spaces all accepted as thousands separators.
//
// The grouped form is listed first and has to contain at least one group, so
// "2664.68" falls through to the plain form and is read whole. Written the
// other way round, "\d{1,3}" matches "266", nothing after it fits, and the
// figure is silently read as R266.
const _numberPattern =
    r'(?:\d{1,3}(?:[ ,.\u00A0\u202F]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)';

const _currencyPattern = r'(ZAR|USD|EUR|GBP|R|\$|£|€)';

// R1 234,56 / R1,234.56 / ZAR 99.99 / $12 / €5,50
// A lookbehind rather than \b, so symbols like $ and € match too while "R"
// still can't match inside a word such as "REFUND".
final _amountRe = RegExp(
  r'(?<![A-Za-z0-9])' '$_currencyPattern' r'\s?' '($_numberPattern)',
  caseSensitive: false,
);

// "Avail R3 100,00", "Available balance: R4 300,00", "New balance R99",
// "Bal R1 234.56". The keyword must sit right before the amount so the
// transaction amount itself is never mistaken for a balance.
final _balanceRe = RegExp(
  r'(?:avail(?:able)?(?:\s+(?:bal(?:ance)?|funds|credit))?|(?:new\s+|closing\s+|current\s+)?bal(?:ance)?)'
  r'\s*(?:is|of|:|=)?\s*'
  '$_currencyPattern'
  r'\s?'
  '($_numberPattern)',
  caseSensitive: false,
);

// Account digits together with whatever direction word sits in front of them,
// so "paid to a/c **8754" stays distinguishable from "debited from a/c
// **8754". Group 1 is the direction word — absent when the message merely
// names an account — and groups 2 and 3 are the digits of the labelled form
// ("acc ..1234", "card ending 1234", "a/c *5678", "account xxxx9012") and of
// the bare masked form ("**8754").
final _accountRefRe = RegExp(
  r'(?:(?<![A-Za-z])(to|into|from)\s+)?'
  r'(?:'
  r'(?<![A-Za-z])(?:a/c|acc(?:ount)?|card|cc)\s*(?:no\.?|number|ending(?:\s+in)?|end(?:ing)?)?\s*[:\-]?\s*[*x.•\s]{0,6}(\d{4})\b'
  r'|(?:[*x•]{2,}|\.{2,})\s?(\d{4})\b'
  r')',
  caseSensitive: false,
);

// "Ref: KEIRA TICKET", "Reference SALARY AUG", "ref no. INV-00912"
final _referenceRe = RegExp(
  r"(?<![A-Za-z])ref(?:erence)?\s*(?:no\.?|number)?\s*[:#\-]?\s*"
  r"([A-Za-z0-9][A-Za-z0-9 &'\-/]{0,39}?)\s*(?=[.,;]|$)",
  caseSensitive: false,
);

// The moment the bank stamped on the transaction, in the shapes SA banks use:
// "2026-08-04 02:03", "04 Aug 26 at 02:03", "04/08/2026 02:03".
final _isoStampRe = RegExp(
  r'(?<![\d/])(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T,]+(?:at\s+)?(\d{1,2}):(\d{2}))?',
);
final _monthStampRe = RegExp(
  r'(?<![A-Za-z0-9])(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?'
  r'(?:\s+(\d{2,4})(?!:))?(?:[ ,]+(?:at\s+)?(\d{1,2}):(\d{2}))?',
  caseSensitive: false,
);
final _slashStampRe = RegExp(
  r'(?<![\d/])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?:[ ,]+(?:at\s+)?(\d{1,2}):(\d{2}))?',
);
final _timeOnlyRe = RegExp(r'(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])');

const _monthNames = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

// "at PICK N PAY", "to John Smith", "from Acme Ltd"
final _merchantRe = RegExp(
  r"\b(?:at|to|from)\s+([A-Z0-9][A-Za-z0-9&@'\-\.]*(?:\s+[A-Z0-9][A-Za-z0-9&@'\-\.]*){0,4})",
);

/// Parses a bank notification into a candidate transaction.
///
/// Everything happens on-device; nothing here performs I/O.
ParsedNotification parseBankNotification({
  required String title,
  required String body,
  String packageName = '',
}) {
  final text = '$title\n$body'.trim();
  if (text.isEmpty) return const ParsedNotification();
  final lower = text.toLowerCase();

  final String bankName = bankPackages[packageName] ??
      _titleiseBank(
        _bankNamesInText.firstWhere((b) => lower.contains(b), orElse: () => ''),
      );

  // Reject balance updates, OTPs, marketing and declined payments outright.
  final isNoise = _noiseWords.any(lower.contains);

  // Read the balance first so its digits can be excluded when looking for the
  // transaction amount — otherwise "Available balance R4 300 after purchase of
  // R150" would read the balance as the purchase.
  final balanceMatch = _balanceRe.firstMatch(text);
  final balanceCents =
      balanceMatch == null ? null : _toCents(balanceMatch.group(2)!);

  final amountMatch = _amountRe.allMatches(text).where((m) {
    if (balanceMatch == null) return true;
    return m.start < balanceMatch.start || m.start >= balanceMatch.end;
  }).firstOrNull;

  if (amountMatch == null || isNoise) {
    return ParsedNotification(
      bankName: bankName,
      availableBalanceCents: isNoise ? null : balanceCents,
    );
  }

  final refs = _readAccountRefs(text);
  final reference = _readReference(text);
  final stampedAt = _readStamp(text);

  final symbolRaw = amountMatch.group(1) ?? '';
  final amountCents = _toCents(amountMatch.group(2)!);
  if (amountCents == null || amountCents <= 0) {
    return ParsedNotification(bankName: bankName);
  }

  // Direction: whichever keyword appears first wins, so "refund of R50 for a
  // purchase" reads as a credit.
  final debitAt = _firstIndexOf(lower, _debitWords);
  final creditAt = _firstIndexOf(lower, _creditWords);
  TxType? type;
  if (debitAt >= 0 && creditAt >= 0) {
    type = debitAt < creditAt ? TxType.expense : TxType.income;
  } else if (debitAt >= 0) {
    type = TxType.expense;
  } else if (creditAt >= 0) {
    type = TxType.income;
  }
  if (type == TxType.income && lower.contains('refund')) type = TxType.refund;

  // Until we know which numbers are the user's, the first one the message
  // names is our best guess at the account it concerns. [resolveOwnership]
  // revisits this once the user's own digits are available.
  final last4 = refs.isEmpty ? '' : refs.first.last4;

  var merchant = _merchantRe.firstMatch(body)?.group(1)?.trim() ?? '';
  merchant = _cleanMerchant(merchant);

  var confidence = 0.4;
  if (type != null) confidence += 0.3;
  if (last4.isNotEmpty) confidence += 0.15;
  if (merchant.isNotEmpty) confidence += 0.1;
  if (bankName.isNotEmpty) confidence += 0.05;

  return ParsedNotification(
    amountCents: amountCents,
    currencySymbol: _normaliseSymbol(symbolRaw),
    type: type,
    merchant: merchant,
    availableBalanceCents: balanceCents,
    accountLast4: last4,
    accountRefs: refs,
    bankName: bankName,
    reference: reference,
    stampedAt: stampedAt,
    confidence: confidence.clamp(0.0, 1.0),
  );
}

/// Decides whose money moved, by checking the account numbers the message
/// named against [ownLast4] — the last four digits of the user's own accounts.
///
/// This matters because the digits in "R350,00 paid to a/c ••8754" belong to
/// whoever was *paid*. If they are the user's, money arrived; if they belong
/// to someone else, the message is about a payment out of an account of the
/// user's that the text never numbers — or about somebody else's account
/// entirely, which is not the user's transaction at all.
///
/// With no numbers to compare against, the reading is left exactly as parsed.
ParsedNotification resolveOwnership(
  ParsedNotification parsed,
  Set<String> ownLast4,
) {
  if (parsed.accountRefs.isEmpty || ownLast4.isEmpty) return parsed;

  final mine =
      parsed.accountRefs.where((r) => ownLast4.contains(r.last4)).firstOrNull;
  final theirs =
      parsed.accountRefs.where((r) => !ownLast4.contains(r.last4)).firstOrNull;

  if (mine == null) {
    // Every number in the message belongs to somebody else. Keep the digits
    // as the counterparty's so nothing tries to match them to an account.
    return parsed.copyWith(
      accountLast4: '',
      counterpartyLast4: theirs!.last4,
      ownership: Ownership.someoneElse,
      confidence: (parsed.confidence - 0.15).clamp(0.0, 1.0),
    );
  }

  // The wording around the user's own number says which way the money went,
  // and it outranks the keyword guess: "paid to" a *different* account is an
  // expense, "paid to" the user's own account is money arriving.
  final type = switch (mine.role) {
    AccountRole.destination =>
      parsed.type == TxType.refund ? TxType.refund : TxType.income,
    AccountRole.source => TxType.expense,
    AccountRole.unspecified => parsed.type,
  };

  return parsed.copyWith(
    type: type,
    accountLast4: mine.last4,
    counterpartyLast4: theirs?.last4 ?? '',
    ownership: Ownership.mine,
    confidence: (parsed.confidence + 0.1).clamp(0.0, 1.0),
  );
}

/// Every account number in [text], each tagged with the direction word in
/// front of it. Repeats of the same number and role are collapsed.
List<AccountRef> _readAccountRefs(String text) {
  final refs = <AccountRef>[];
  for (final m in _accountRefRe.allMatches(text)) {
    final digits = m.group(2) ?? m.group(3);
    if (digits == null) continue;
    final role = switch (m.group(1)?.toLowerCase()) {
      'to' || 'into' => AccountRole.destination,
      'from' => AccountRole.source,
      _ => AccountRole.unspecified,
    };
    final ref = AccountRef(digits, role);
    if (!refs.contains(ref)) refs.add(ref);
  }
  return refs;
}

String _readReference(String text) {
  final raw = _referenceRe.firstMatch(text)?.group(1)?.trim() ?? '';
  return raw.replaceAll(RegExp(r'\s+'), ' ');
}

/// The transaction time the bank wrote into the message, as "MM-DD HH:mm".
///
/// Two fixed slots, either of which may be blank when the message left it
/// out, so "2026-08-04 02:03" and "04 Aug 26 at 02:03" — the same event told
/// by two different apps — come out identical, and a copy that gives only
/// part of it can still be compared on the part it gives.
///
/// The year is dropped: it never distinguishes two reports that arrived
/// within days of each other, and only one of two copies tends to carry it.
String _readStamp(String text) {
  final iso = _isoStampRe.firstMatch(text);
  if (iso != null) {
    return _formatStamp(
      month: int.tryParse(iso.group(2)!),
      day: int.tryParse(iso.group(3)!),
      hour: iso.group(4),
      minute: iso.group(5),
    );
  }

  final named = _monthStampRe.firstMatch(text);
  if (named != null) {
    return _formatStamp(
      month: _monthNames.indexOf(named.group(2)!.toLowerCase().substring(0, 3)) + 1,
      day: int.tryParse(named.group(1)!),
      hour: named.group(4),
      minute: named.group(5),
    );
  }

  final slashed = _slashStampRe.firstMatch(text);
  if (slashed != null) {
    return _formatStamp(
      // Day first: SA banks write 04/08/2026 for 4 August.
      month: int.tryParse(slashed.group(2)!),
      day: int.tryParse(slashed.group(1)!),
      hour: slashed.group(4),
      minute: slashed.group(5),
    );
  }

  final time = _timeOnlyRe.firstMatch(text);
  if (time != null) {
    return _formatStamp(hour: time.group(1), minute: time.group(2));
  }
  return '';
}

String _formatStamp({int? month, int? day, String? hour, String? minute}) {
  final date = month != null && month >= 1 && month <= 12 && day != null
      ? '${_pad(month)}-${_pad(day)}'
      : '';
  final time = hour != null && minute != null
      ? '${_pad(int.parse(hour))}:$minute'
      : '';
  return date.isEmpty && time.isEmpty ? '' : '$date $time';
}

String _pad(int n) => n.toString().padLeft(2, '0');

int _firstIndexOf(String haystack, List<String> needles) {
  var best = -1;
  for (final n in needles) {
    final i = haystack.indexOf(n);
    if (i >= 0 && (best < 0 || i < best)) best = i;
  }
  return best;
}

/// Handles both "1,234.56" and "1 234,56" styles.
int? _toCents(String raw) {
  var s = raw.replaceAll(RegExp(r'[\u00A0\u202F]'), ' ').trim();
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  final decimalSep = lastComma > lastDot ? ',' : (lastDot > -1 ? '.' : '');

  if (decimalSep.isEmpty) {
    s = s.replaceAll(RegExp(r'[ ,.]'), '');
    final whole = int.tryParse(s);
    return whole == null ? null : whole * 100;
  }

  final sepIndex = decimalSep == ',' ? lastComma : lastDot;
  final decimals = s.substring(sepIndex + 1);
  // Three digits after the separator means it was a thousands separator.
  if (decimals.length == 3) {
    final whole = int.tryParse(s.replaceAll(RegExp(r'[ ,.]'), ''));
    return whole == null ? null : whole * 100;
  }
  final wholePart = s.substring(0, sepIndex).replaceAll(RegExp(r'[ ,.]'), '');
  final whole = int.tryParse(wholePart.isEmpty ? '0' : wholePart);
  if (whole == null) return null;
  final frac = int.tryParse(decimals.padRight(2, '0').substring(0, 2)) ?? 0;
  return whole * 100 + frac;
}

String _normaliseSymbol(String raw) {
  final s = raw.toUpperCase();
  return switch (s) {
    'ZAR' => 'R',
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    _ => raw,
  };
}

String _cleanMerchant(String raw) {
  var m = raw.trim();
  // Drop trailing date/reference fragments the regex may have swept up.
  m = m.replaceAll(
      RegExp(r'\s+(on|ref|reference|using|with|avail\w*)\b.*$', caseSensitive: false), '');
  m = m.replaceAll(RegExp(r'[\s.,;:]+$'), '');
  if (m.length > 60) m = m.substring(0, 60).trim();
  // A bare number isn't a merchant name.
  if (RegExp(r'^\d+$').hasMatch(m)) return '';
  return m;
}

String _titleiseBank(String s) {
  if (s.isEmpty) return '';
  return switch (s) {
    'fnb' => 'FNB',
    'std bank' || 'standard bank' => 'Standard Bank',
    'tyme' || 'tymebank' => 'TymeBank',
    'discovery bank' => 'Discovery Bank',
    'african bank' => 'African Bank',
    _ => s[0].toUpperCase() + s.substring(1),
  };
}
