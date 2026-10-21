/// ─── The online-payment processing fee ────────────────────────────────
///
/// A family paying a fee balance online pays a processing fee on top; the
/// school is always credited the full amount they chose to pay. The server is
/// the authority — `src/services/transactionFeeCore.js` calculates it and
/// returns the real figures when a checkout opens — so this exists only to tell
/// a parent, BEFORE they continue, what the total will be. Keep the rate in
/// step with that file.
library;

const double transactionFeeRate = 0.045;

class FeeQuote {
  /// What the student's account is credited with.
  final int amount;

  /// The processing fee added on top.
  final int fee;

  /// What the parent will actually be charged.
  final int total;

  const FeeQuote({required this.amount, required this.fee, required this.total});
}

FeeQuote quoteFee(int amount) {
  final base = amount < 0 ? 0 : amount;
  final fee = (base * transactionFeeRate).round();
  return FeeQuote(amount: base, fee: fee, total: base + fee);
}
