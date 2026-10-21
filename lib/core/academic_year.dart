/// ─── Academic years and terms ─────────────────────────────────────────
///
/// Pure helpers, mirroring `src/services/academicTermCore.js` and
/// `yearOfTerm()` in `src/services/termFeesCore.js` on the web — keep the three
/// in step. A school year here runs September to August, and a term is named
/// for the year it ENDS in: "Term 1 2026" is September to December 2025 and so
/// belongs to the academic year "2025/2026".
///
/// The app used to carry the year as a fixed constant ("2025/2026"), which went
/// quietly wrong the day the school year turned: fee charges and payments for
/// the new year were filtered out, and anything the app wrote was filed under
/// the old one.
library;

final RegExp _termPattern = RegExp(r'^Term\s+(\d)\s+(\d{4})$', caseSensitive: false);

/// "Term 2 2026" → "2025/2026". Empty when [term] is not a full term name.
String academicYearForTerm(String term) {
  final m = _termPattern.firstMatch(term.trim());
  if (m == null) return '';
  final year = int.parse(m.group(2)!);
  return '${year - 1}/$year';
}

/// The academic year a date falls in, for a school that has set no term yet.
/// September onward belongs to the year that ends next August.
String academicYearForDate(DateTime date) {
  final startYear = date.month >= 9 ? date.year : date.year - 1;
  return '$startYear/${startYear + 1}';
}

/// A number that sorts fee lines and terms oldest-first.
///
/// Handles the full form ("Term 2 2026"), the older short form ("Term 2", with
/// the academic year alongside) and "Full Year", which is billed with Term 1.
int termSortKey(String term, {String academicYear = ''}) {
  final full = _termPattern.firstMatch(term.trim());
  if (full != null) return int.parse(full.group(2)!) * 10 + int.parse(full.group(1)!);

  final endYear = _endYearOf(academicYear);
  final short = RegExp(r'^Term\s+(\d)$', caseSensitive: false).firstMatch(term.trim());
  if (short != null) return endYear * 10 + int.parse(short.group(1)!);
  if (term.trim().toLowerCase() == 'full year') return endYear * 10 + 1;

  return endYear * 10;
}

int _endYearOf(String academicYear) {
  final m = RegExp(r'^(\d{4})/(\d{4})$').firstMatch(academicYear.trim());
  return m == null ? 0 : int.parse(m.group(2)!);
}
