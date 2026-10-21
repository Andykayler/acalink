import 'package:flutter_test/flutter_test.dart';

import 'package:acalink/core/academic_year.dart';
import 'package:acalink/core/transaction_fee.dart';

void main() {
  group('academicYearForTerm', () {
    test('a term belongs to the year it ends in', () {
      expect(academicYearForTerm('Term 1 2026'), '2025/2026');
      expect(academicYearForTerm('Term 3 2026'), '2025/2026');
      expect(academicYearForTerm('Term 1 2027'), '2026/2027');
    });
    test('anything that is not a full term name gives nothing', () {
      expect(academicYearForTerm(''), '');
      expect(academicYearForTerm('Term 2'), '');
      expect(academicYearForTerm('Full Year'), '');
    });
  });

  group('academicYearForDate', () {
    test('September starts the new year', () {
      expect(academicYearForDate(DateTime(2026, 8, 31)), '2025/2026');
      expect(academicYearForDate(DateTime(2026, 9, 1)), '2026/2027');
      expect(academicYearForDate(DateTime(2026, 10, 20)), '2026/2027');
      expect(academicYearForDate(DateTime(2027, 1, 15)), '2026/2027');
    });
  });

  group('termSortKey', () {
    test('orders full, short and full-year terms oldest first', () {
      final terms = <String, int>{
        'old': termSortKey('Term 3', academicYear: '2024/2025'),
        'fullYear': termSortKey('Full Year', academicYear: '2025/2026'),
        'short2': termSortKey('Term 2', academicYear: '2025/2026'),
        'full': termSortKey('Term 1 2027'),
      };
      final ordered = terms.keys.toList()..sort((a, b) => terms[a]!.compareTo(terms[b]!));
      expect(ordered, ['old', 'fullYear', 'short2', 'full']);
    });
  });

  group('quoteFee', () {
    test('adds 4.5% on top and leaves the credited amount whole', () {
      final q = quoteFee(100000);
      expect(q.amount, 100000);
      expect(q.fee, 4500);
      expect(q.total, 104500);
    });
    test('handles nothing', () {
      expect(quoteFee(0).total, 0);
      expect(quoteFee(-5).total, 0);
    });
  });
}
