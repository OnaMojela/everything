import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Canonical day key used everywhere a record is keyed by calendar day.
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDayKey(String key) => DateTime.parse(key);
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime get today => dateOnly(DateTime.now());

String formatDay(DateTime d) {
  final t = today;
  final that = dateOnly(d);
  final diff = that.difference(t).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (d.year == t.year) return DateFormat('EEE, d MMM').format(d);
  return DateFormat('d MMM yyyy').format(d);
}

String formatFullDay(DateTime d) => DateFormat('EEEE, d MMMM').format(d);
String formatMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);
String formatTimeOfDayMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

final _compactNum = NumberFormat.compact();
String compactNumber(num n) => _compactNum.format(n);

/// All money is stored as integer cents; formatting happens only at the edge.
String formatMoney(int cents, String symbol, {bool signed = false}) {
  final amount = cents / 100.0;
  final f = NumberFormat('#,##0.00');
  final sign = signed ? (cents > 0 ? '+' : (cents < 0 ? '−' : '')) : (cents < 0 ? '−' : '');
  return '$sign$symbol${f.format(amount.abs())}';
}

/// Parse user input like "12,50" / "12.5" into cents. Null when invalid.
int? parseMoneyToCents(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v == null ? null : (v * 100).round();
}

/// Cents -> text for pre-filling amount fields ("12.5", "12").
String centsToEditText(int cents) =>
    cents % 100 == 0 ? (cents ~/ 100).toString() : (cents / 100).toStringAsFixed(2);

/// Trims trailing zeros: 2.0 -> "2", 2.50 -> "2.5"
String trimNum(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

DateTime startOfWeek(DateTime d, {bool mondayStart = true}) {
  final day = dateOnly(d);
  final shift = mondayStart ? day.weekday - 1 : day.weekday % 7;
  return day.subtract(Duration(days: shift));
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
