/// Normalises Malawian numbers to E.164 (+265XXXXXXXXX) so lookups against
/// `guardianPhone` in Firestore match regardless of how the parent types it
/// (0991234567, 099 123 4567, +265991234567, 265991234567, etc).
/// Mirrors the web admin's `normalisePhone` helper — keep both in sync.
String normalisePhone(String raw) {
  var digits = raw.trim().replaceAll(RegExp(r'[\s\-()]'), '');

  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  }

  if (digits.startsWith('265')) {
    return '+$digits';
  }

  if (digits.startsWith('0') && digits.length == 10) {
    return '+265${digits.substring(1)}';
  }

  if (digits.length == 9) {
    // e.g. "991234567" typed without the leading 0
    return '+265$digits';
  }

  // Fallback: return as typed with a + so Firestore comparisons are consistent,
  // even if it doesn't match the expected Malawi format.
  return digits.startsWith('+') ? digits : '+$digits';
}