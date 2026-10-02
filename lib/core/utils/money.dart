import 'package:intl/intl.dart';

/// Formats and parses money.
///
/// Amounts are stored as integer paise throughout (see `MembershipPlans
/// .priceMinor`): floating point accumulates rounding error across revenue
/// reports, so rupees only exist at the display and input boundary.
class Money {
  const Money._();

  static const int minorPerMajor = 100;

  static final NumberFormat _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _rupeesWithPaise = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Formats paise for display, e.g. 150000 -> "₹1,500".
  ///
  /// Whole rupee amounts drop the decimals — gym plans are priced in whole
  /// rupees, and "₹1,500.00" is noise on a list of them.
  static String format(int minor) {
    final hasPaise = minor % minorPerMajor != 0;
    final major = minor / minorPerMajor;
    return hasPaise ? _rupeesWithPaise.format(major) : _rupees.format(major);
  }

  /// Parses user input in rupees into paise. Returns null if unparseable.
  ///
  /// Accepts "1500", "1,500", "₹1500", "1500.50".
  static int? parse(String input) {
    final cleaned = input
        .replaceAll('₹', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();
    if (cleaned.isEmpty) return null;

    final major = double.tryParse(cleaned);
    if (major == null || major.isNaN || major.isInfinite) return null;
    if (major < 0) return null;

    // Round rather than truncate: 10.555 should be 1056 paise, not 1055.
    return (major * minorPerMajor).round();
  }

  /// Paise as a plain rupee string for prefilling an input, e.g. "1500".
  static String toInput(int minor) {
    if (minor % minorPerMajor == 0) {
      return (minor ~/ minorPerMajor).toString();
    }
    return (minor / minorPerMajor).toStringAsFixed(2);
  }
}

/// Formats a plan duration in the units people actually say.
String formatDuration(int days) {
  if (days % 365 == 0) {
    final years = days ~/ 365;
    return years == 1 ? '1 year' : '$years years';
  }
  if (days % 30 == 0) {
    final months = days ~/ 30;
    return months == 1 ? '1 month' : '$months months';
  }
  if (days % 7 == 0) {
    final weeks = days ~/ 7;
    return weeks == 1 ? '1 week' : '$weeks weeks';
  }
  return days == 1 ? '1 day' : '$days days';
}
