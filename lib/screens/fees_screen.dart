import 'package:flutter/material.dart';
import '../models/student.dart';
import '../theme/app_colors.dart';
import '../services/fees_service.dart';
import '../widgets/payment_sheet.dart';

/// ─── Screen ────────────────────────────────────────────────────────────
class FeesScreen extends StatefulWidget {
  final Student? student;
  /// Shown as `recordedBy` on the payment doc — matches what the bursar
  /// console shows in its "Recorded by" / receipt fields. Pass the
  /// signed-in parent/guardian's name.
  final String guardianName;
  const FeesScreen({super.key, this.student, required this.guardianName});

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  final _service = FeesService();

  List<FeeLine> _lines = [];
  List<PaymentRecord> _payments = [];
  bool _loading = true;
  String? _error;

  /// Money the family has reported but the school has not confirmed. Shown
  /// beside the balance rather than inside it — it has not reached the school,
  /// so it cannot reduce what is owed, but a parent who reported it needs to
  /// see that it did not vanish.
  int _awaitingConfirmation = 0;

  int get _totalCharged => _lines.fold(0, (s, l) => s + l.charged);
  int get _totalPaid => _lines.fold(0, (s, l) => s + l.paid);
  int get _balance => _totalCharged - _totalPaid;
  double get _percentPaid =>
      _totalCharged == 0 ? 0 : _totalPaid / _totalCharged;

  @override
  void initState() {
    super.initState();
    _loadFees();
  }

  Future<void> _loadFees() async {
    final student = widget.student;
    if (student == null) {
      setState(() {
        _loading = false;
        _error = "No student selected";
      });
      return;
    }

    try {
      final data = await _service.fetchStudentFees(student);
      if (!mounted) return;
      setState(() {
        _lines = data.lines;
        _payments = data.payments;
        _awaitingConfirmation = data.awaitingConfirmation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Failed to load fees: $e";
      });
    }
  }

  Future<void> _openPaymentSheet() async {
    final student = widget.student;
    if (student == null) return;

    final result = await showModalBottomSheet<PaymentRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentSheet(
        student: student,
        outstandingBalance: _balance,
        recordedBy: widget.guardianName,
        service: _service,
      ),
    );

    if (result == null || !mounted) return;

    if (result.verified) {
      // Confirmed by the gateway, so the balance really has moved. Applied
      // optimistically here; the service owns the distribution logic.
      setState(() {
        _payments.insert(0, result);
        _lines = _service.applyPayment(_lines, result.amount);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.success,
          content: Text(
            'Payment of ${formatCurrency(result.amount)} received'
            '${result.receiptNo.isNotEmpty ? ' · Receipt ${result.receiptNo}' : ''}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
      return;
    }

    // Reported, not paid. The balance is deliberately left alone — moving it
    // here is what used to let a family believe their fees were settled when
    // the school had received nothing.
    setState(() {
      _payments.insert(0, result);
      _awaitingConfirmation += result.amount;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.primary,
        content: Text(
          '${formatCurrency(result.amount)} sent to the school — awaiting confirmation',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.student?.fullName ?? 'Student';

    if (_loading) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(child: Text(_error!, style: TextStyle(color: context.colors.danger))),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _FeesHeader(studentName: name)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _BalanceCard(
                  totalCharged: _totalCharged,
                  totalPaid: _totalPaid,
                  balance: _balance,
                  percent: _percentPaid,
                  awaitingConfirmation: _awaitingConfirmation,
                  onPay: _balance > 0 ? _openPaymentSheet : null,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _FeeBreakdownCard(lines: _lines),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverToBoxAdapter(
                child: _PaymentHistoryCard(payments: _payments),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─── Header ────────────────────────────────────────────────────────────
class _FeesHeader extends StatelessWidget {
  final String studentName;
  const _FeesHeader({required this.studentName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_rounded, color: context.colors.textPrimary),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FEES',
                  style: TextStyle(
                    fontFamily: context.colors.fontMono,
                    fontSize: 9,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  studentName,
                  style: TextStyle(
                    fontFamily: context.colors.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Balance summary + pay CTA ────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final int totalCharged;
  final int totalPaid;
  final int balance;
  final double percent;
  final int awaitingConfirmation;
  final VoidCallback? onPay;

  const _BalanceCard({
    required this.totalCharged,
    required this.totalPaid,
    required this.balance,
    required this.percent,
    required this.onPay,
    this.awaitingConfirmation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final settled = balance <= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.colors.navyStart, context.colors.navyEnd],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                settled ? 'FULLY SETTLED' : 'OUTSTANDING BALANCE',
                style: TextStyle(
                  fontFamily: context.colors.fontMono,
                  fontSize: 9,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.65),
                ),
              ),
              if (!settled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'DUE 5 AUG 2026',
                    style: TextStyle(
                      fontFamily: context.colors.fontMono,
                      fontSize: 8.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            settled ? formatCurrency(0) : formatCurrency(balance),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent.clamp(0, 1),
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(
                settled ? context.colors.success : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatCurrency(totalPaid)} paid of ${formatCurrency(totalCharged)} · ${(percent * 100).round()}%',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
          ),
          // Reported but unconfirmed money, named as such and kept out of the
          // figures above. Hiding it would look like the report was lost;
          // counting it would tell the family they owe less than they do.
          if (awaitingConfirmation > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.white.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${formatCurrency(awaitingConfirmation)} awaiting the school\'s confirmation',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPay,
              style: ElevatedButton.styleFrom(
                backgroundColor: settled ? Colors.white.withOpacity(0.12) : Colors.white,
                foregroundColor: settled ? Colors.white.withOpacity(0.6) : context.colors.navyStart,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(settled ? Icons.check_circle_rounded : Icons.payments_rounded,
                  size: 18),
              label: Text(
                settled ? 'No balance due' : 'Make a Payment',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Fee breakdown ─────────────────────────────────────────────────────
class _FeeBreakdownCard extends StatelessWidget {
  final List<FeeLine> lines;
  const _FeeBreakdownCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10, left: 2),
          child: Text(
            'Fee Breakdown',
            style: TextStyle(
              fontFamily: context.colors.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < lines.length; i++) ...[
                _FeeLineRow(line: lines[i]),
                if (i != lines.length - 1)
                  Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusStyle {
  final Color color;
  final Color bg;
  final String label;
  const _StatusStyle(this.color, this.bg, this.label);
}

Map<FeeStatus, _StatusStyle> _statusStyles(AppColors c) => {
      FeeStatus.paid: _StatusStyle(c.success, c.successPale, 'PAID'),
      FeeStatus.partial: _StatusStyle(c.warning, c.warningPale, 'PARTIAL'),
      FeeStatus.unpaid: _StatusStyle(c.danger, c.dangerPale, 'UNPAID'),
    };

class _FeeLineRow extends StatelessWidget {
  final FeeLine line;
  const _FeeLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final style = _statusStyles(context.colors)[line.status]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500, color: context.colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  line.balance > 0
                      ? '${formatCurrency(line.paid)} of ${formatCurrency(line.charged)} paid'
                      : '${formatCurrency(line.charged)} settled',
                  style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration:
                BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(7)),
            child: Text(
              style.label,
              style: TextStyle(
                fontFamily: context.colors.fontMono,
                fontSize: 8.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: style.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Payment history ───────────────────────────────────────────────────
class _PaymentHistoryCard extends StatelessWidget {
  final List<PaymentRecord> payments;
  const _PaymentHistoryCard({required this.payments});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10, left: 2),
          child: Text(
            'Payment History',
            style: TextStyle(
              fontFamily: context.colors.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          child: payments.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('No payments recorded yet',
                        style: TextStyle(fontSize: 12.5, color: context.colors.textMuted)),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < payments.length; i++) ...[
                      _PaymentRow(payment: payments[i]),
                      if (i != payments.length - 1)
                        Divider(height: 1, color: context.colors.border, indent: 16, endIndent: 16),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final PaymentRecord payment;
  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    // A tick means the school has the money. A row the family reported and
    // nobody has checked gets an hourglass and a muted amount — the same
    // record, told truthfully.
    final confirmed = payment.verified;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: confirmed ? context.colors.successPale : context.colors.warningPale,
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(
              confirmed ? Icons.check_rounded : Icons.hourglass_top_rounded,
              size: 16,
              color: confirmed ? context.colors.success : context.colors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.method,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500, color: context.colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  confirmed
                      ? '${payment.date}${payment.reference.isNotEmpty ? ' · Ref ${payment.reference}' : ''}'
                      : '${payment.date} · awaiting the school\'s confirmation',
                  style: TextStyle(
                      fontSize: 11,
                      color: confirmed ? context.colors.textMuted : context.colors.warningDark),
                ),
              ],
            ),
          ),
          Text(formatCurrency(payment.amount),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: confirmed ? context.colors.success : context.colors.textMuted)),
        ],
      ),
    );
  }
}