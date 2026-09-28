import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../models/student.dart';
import '../services/fees_service.dart';
import '../services/paychangu_service.dart';
import '../theme/app_colors.dart';

/// ─── Payment sheet ─────────────────────────────────────────────────────
///
/// Two things a parent might mean by "pay", kept apart because they are not
/// the same act:
///
///   PAY NOW      — money moves, through PayChangu, now. The app hands the
///                  payer to the gateway's own page, then asks our server what
///                  happened. A receipt exists only if PayChangu confirmed it.
///
///   ALREADY PAID — a message to the school about money that moved elsewhere:
///                  a bank counter, cash at the office, a transfer made in the
///                  Airtel app. It reduces nothing and issues no receipt; the
///                  bursar matches it against what actually arrived.
///
/// The previous version of this sheet had only the second path but presented
/// it as the first — "Payment Received", a receipt number, and a balance that
/// dropped on the strength of a typed-in figure. Every part of that was a
/// claim dressed as a fact.
///
/// Returns the completed [PaymentRecord] via `Navigator.pop`, or `null` if
/// dismissed. Check [PaymentRecord.verified] before telling anyone their fees
/// are paid.
class PaymentSheet extends StatefulWidget {
  final Student student;
  final int outstandingBalance;
  final String recordedBy;
  final FeesService service;
  final PayChanguService? gateway;

  const PaymentSheet({
    super.key,
    required this.student,
    required this.outstandingBalance,
    required this.recordedBy,
    required this.service,
    this.gateway,
  });

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

const _payMethodIcons = {
  PayMethod.airtelMoney: Icons.phone_iphone_rounded,
  PayMethod.tnmMpamba: Icons.phone_android_rounded,
  PayMethod.bankTransfer: Icons.account_balance_rounded,
  PayMethod.school: Icons.storefront_rounded,
};

enum _Stage {
  choose,     // pay now, or report something already paid
  payForm,    // amount and term for a gateway payment
  waiting,    // checkout is open in the browser; we poll
  reportForm, // the old form, honestly labelled
  submitting,
  paid,       // confirmed by PayChangu
  reported,   // told the school; nothing settled
  failed,
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final PayChanguService _gateway = widget.gateway ?? PayChanguService();

  late final TextEditingController _amountCtrl;
  final _phoneCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  PayMethod _method = PayMethod.bankTransfer;
  late String _term;
  _Stage _stage = _Stage.choose;
  String? _error;
  String? _notice;

  Checkout? _checkout;
  StreamSubscription<PaymentStatus>? _watch;
  PaymentRecord? _completed;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.outstandingBalance.toString());
    _term = widget.service.availableTerms.first;
    _phoneCtrl.text = widget.student.guardianPhone;
  }

  @override
  void dispose() {
    // A poll left running against a closed sheet keeps asking the gateway
    // about a transaction nobody is looking at. Settlement carries on
    // server-side either way, so there is nothing to lose by stopping.
    _watch?.cancel();
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  PayMethodOption get _selected => payMethods.firstWhere((m) => m.method == _method);

  int? _readAmount() {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return null;
    }
    return amount;
  }

  // ── Pay now, through PayChangu ─────────────────────────────────────────
  Future<void> _payNow() async {
    final amount = _readAmount();
    if (amount == null) return;

    setState(() {
      _error = null;
      _notice = null;
      _stage = _Stage.submitting;
    });

    try {
      final checkout = await _gateway.startCheckout(
        student: widget.student,
        amount: amount,
        term: _term,
        payerName: widget.recordedBy,
        payerPhone: _phoneCtrl.text.trim(),
        academicYear: feesAcademicYear,
      );

      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _stage = _Stage.waiting;
      });

      final opened = await _gateway.openCheckout(checkout.checkoutUrl);
      if (mounted && !opened) {
        setState(() => _notice = 'Could not open your browser. Tap "Open the payment page" below.');
      }

      _startWatching(checkout);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = _Stage.payForm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start the payment. Please try again.';
        _stage = _Stage.payForm;
      });
    }
  }

  void _startWatching(Checkout checkout) {
    _watch?.cancel();
    _watch = _gateway
        .watch(checkout.txRef, onTransientError: (_) {
          // Reported, not fatal — the money may already be moving.
          if (mounted) {
            setState(() => _notice = 'Still checking. Keep this open, or come back later.');
          }
        })
        .listen((status) {
      if (!mounted || status.phase == PaymentPhase.pending) return;

      if (status.phase == PaymentPhase.success) {
        setState(() {
          _completed = PaymentRecord(
            id: status.txRef,
            method: 'PayChangu',
            amount: status.amount,
            date: 'Just now',
            reference: status.txRef,
            receiptNo: status.receiptNo ?? '',
            verified: true,
          );
          _stage = _Stage.paid;
        });
      } else {
        setState(() {
          _error = 'The payment did not go through. Nothing has been charged.';
          _stage = _Stage.failed;
        });
      }
    });
  }

  // ── Report a payment made elsewhere ────────────────────────────────────
  Future<void> _report() async {
    final amount = _readAmount();
    if (amount == null) return;
    if (_selected.needsPhone && _phoneCtrl.text.trim().length < 9) {
      setState(() => _error = 'Enter the number the payment was sent from');
      return;
    }

    setState(() {
      _error = null;
      _stage = _Stage.submitting;
    });

    try {
      final reference = _referenceCtrl.text.trim().isNotEmpty
          ? _referenceCtrl.text.trim()
          : (_selected.needsPhone ? _phoneCtrl.text.trim() : '');

      final record = await widget.service.reportOfflinePayment(
        student: widget.student,
        method: _method,
        amount: amount,
        term: _term,
        recordedBy: widget.recordedBy,
        referenceNo: reference,
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _completed = record;
        _stage = _Stage.reported;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not send this to the school — please try again';
        _stage = _Stage.reportForm;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SafeArea(
          top: false,
          child: switch (_stage) {
            _Stage.choose => _buildChoice(),
            _Stage.payForm => _buildPayForm(),
            _Stage.waiting => _buildWaiting(),
            _Stage.reportForm => _buildReportForm(),
            _Stage.submitting => const _SubmittingView(),
            _Stage.paid => _PaidView(payment: _completed!),
            _Stage.reported => _ReportedView(payment: _completed!),
            _Stage.failed => _FailedView(
                message: _error ?? 'The payment did not go through.',
                onRetry: () => setState(() {
                  _error = null;
                  _notice = null;
                  _stage = _Stage.payForm;
                }),
              ),
          },
        ),
      ),
    );
  }

  // ── Screens ────────────────────────────────────────────────────────────

  Widget _buildChoice() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        _title('Fees'),
        Text(
          'Outstanding balance: ${formatCurrency(widget.outstandingBalance)}',
          style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary),
        ),
        const SizedBox(height: 20),
        _ChoiceTile(
          icon: Icons.smartphone_rounded,
          title: 'Pay now',
          subtitle: 'Airtel Money, TNM Mpamba or card. Confirmed straight away.',
          highlight: true,
          onTap: () => setState(() => _stage = _Stage.payForm),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          icon: Icons.receipt_long_rounded,
          title: 'I have already paid',
          subtitle: 'Tell the school about a payment made at the bank or the office.',
          onTap: () => setState(() => _stage = _Stage.reportForm),
        ),
        const SizedBox(height: 14),
        Text(
          'Only a payment made here is confirmed immediately. Anything you report is '
          'checked by the school before it comes off your balance.',
          style: TextStyle(fontSize: 11.5, height: 1.5, color: context.colors.textMuted),
        ),
      ],
    );
  }

  Widget _buildPayForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grabber(),
          _title('Pay now'),
          Text(
            'You will finish on PayChangu\'s secure page. Acalink never sees your PIN or '
            'card number.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 20),
          _label('AMOUNT (MWK)'),
          _field(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Part-payment is fine — pay what you can now.',
            style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
          ),
          const SizedBox(height: 18),
          _label('TERM'),
          _termPicker(),
          const SizedBox(height: 18),
          _label('MOBILE MONEY NUMBER'),
          _field(controller: _phoneCtrl, keyboardType: TextInputType.phone, hintText: '099X XXX XXX'),
          const SizedBox(height: 6),
          Text(
            'The handset that will approve the payment.',
            style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
          ),
          if (_error != null) _errorRow(_error!),
          const SizedBox(height: 20),
          _primaryButton('Continue to PayChangu', _payNow),
          const SizedBox(height: 8),
          _backButton(),
        ],
      ),
    );
  }

  Widget _buildWaiting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: context.colors.primary),
              ),
              const SizedBox(height: 14),
              Text('Waiting for your payment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
              const SizedBox(height: 4),
              Text(formatCurrency(_checkout?.amount ?? 0),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
              const SizedBox(height: 2),
              Text(_checkout?.txRef ?? '',
                  style: TextStyle(
                      fontFamily: context.colors.fontMono, fontSize: 11, color: context.colors.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _step(1, 'Choose Airtel Money, TNM Mpamba or card on the page that opened.'),
        _step(2, 'Approve the prompt on your phone.'),
        _step(3, 'Come back here — this updates by itself.'),
        if (_notice != null) ...[
          const SizedBox(height: 10),
          Text(_notice!, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.border),
          ),
          child: Text(
            'You can close this. Your payment is confirmed on Acalink\'s servers whether or '
            'not this page is open, and the receipt appears here once it clears.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: context.colors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              final url = _checkout?.checkoutUrl;
              if (url != null) _gateway.openCheckout(url);
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: BorderSide(color: context.colors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Open the payment page', style: TextStyle(fontSize: 13.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildReportForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grabber(),
          _title('Tell the school you have paid'),
          Text(
            'For money already sent another way. The bursar checks it against the school\'s '
            'records before it comes off your balance — this is not a receipt.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 20),
          _label('AMOUNT PAID (MWK)'),
          _field(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 18),
          _label('TERM'),
          _termPicker(),
          const SizedBox(height: 18),
          _label('HOW YOU PAID'),
          const SizedBox(height: 2),
          ...payMethods.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MethodTile(
                  option: m,
                  selected: _method == m.method,
                  onTap: () => setState(() => _method = m.method),
                ),
              )),
          if (_selected.needsPhone) ...[
            const SizedBox(height: 4),
            _label('NUMBER YOU PAID FROM'),
            _field(controller: _phoneCtrl, keyboardType: TextInputType.phone, hintText: '099X XXX XXX'),
          ],
          const SizedBox(height: 18),
          _label('REFERENCE / TRANSACTION NO.'),
          _field(controller: _referenceCtrl, hintText: 'Helps the bursar find your payment'),
          const SizedBox(height: 18),
          _label('NOTES (OPTIONAL)'),
          _field(controller: _notesCtrl, maxLines: 2),
          if (_error != null) _errorRow(_error!),
          const SizedBox(height: 20),
          _primaryButton('Send to the school', _report),
          const SizedBox(height: 8),
          _backButton(),
        ],
      ),
    );
  }

  // ── Small pieces ───────────────────────────────────────────────────────

  Widget _grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: context.colors.borderStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontFamily: context.colors.fontMono,
                fontSize: 9,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: context.colors.textMuted)),
      );

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: context.colors.primaryPale, shape: BoxShape.circle),
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.primaryLight)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: context.colors.textSecondary)),
            ),
          ],
        ),
      );

  Widget _errorRow(String message) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 15, color: context.colors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(message, style: TextStyle(fontSize: 12, color: context.colors.danger)),
            ),
          ],
        ),
      );

  Widget _termPicker() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _term,
            isExpanded: true,
            items: [
              for (final t in widget.service.availableTerms)
                DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14))),
            ],
            onChanged: (v) => setState(() => _term = v ?? _term),
          ),
        ),
      );

  Widget _primaryButton(String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.navyStart,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _backButton() => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => setState(() {
            _error = null;
            _stage = _Stage.choose;
          }),
          child: Text('Back', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextStyle? style,
    String? hintText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: style ?? TextStyle(fontSize: 14, color: context.colors.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: context.colors.cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highlight ? context.colors.primaryPale : context.colors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight ? context.colors.primary : context.colors.border,
              width: highlight ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: highlight ? context.colors.primaryLight : context.colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: highlight ? context.colors.primaryLight : context.colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11.5, height: 1.4, color: context.colors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final PayMethodOption option;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryPale : context.colors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? context.colors.primary : context.colors.border,
                width: selected ? 1.3 : 1),
          ),
          child: Row(
            children: [
              Icon(_payMethodIcons[option.method],
                  size: 17,
                  color: selected ? context.colors.primaryLight : context.colors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected ? context.colors.primaryLight : context.colors.textPrimary,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? context.colors.primary : context.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmittingView extends StatelessWidget {
  const _SubmittingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: context.colors.primary),
          ),
          const SizedBox(height: 16),
          Text('One moment…',
              style: TextStyle(fontSize: 13.5, color: context.colors.textSecondary)),
        ],
      ),
    );
  }
}

/// Money confirmed by the gateway. This is the only screen in the app allowed
/// to say a payment was received.
class _PaidView extends StatelessWidget {
  final PaymentRecord payment;
  const _PaidView({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: context.colors.successPale, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.check_rounded, size: 28, color: context.colors.success),
        ),
        const SizedBox(height: 16),
        Text('Payment received',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
        const SizedBox(height: 4),
        Text(formatCurrency(payment.amount),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          payment.receiptNo.isNotEmpty
              ? 'Confirmed by PayChangu · Receipt ${payment.receiptNo}'
              : 'Confirmed by PayChangu',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.colors.textMuted),
        ),
        const SizedBox(height: 22),
        _DoneButton(payment: payment),
      ],
    );
  }
}

/// A message sent, not a payment made. Everything about this screen is worded
/// to keep that clear — no tick, no receipt, no claim that anything is settled.
class _ReportedView extends StatelessWidget {
  final PaymentRecord payment;
  const _ReportedView({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: context.colors.primaryPale, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.mark_email_read_outlined, size: 26, color: context.colors.primaryLight),
        ),
        const SizedBox(height: 16),
        Text('Sent to the school',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
        const SizedBox(height: 4),
        Text(formatCurrency(payment.amount),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'The bursar will check this against the school\'s records. Your balance changes '
            'once they confirm it — until then it shows as awaiting confirmation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5, color: context.colors.textSecondary),
          ),
        ),
        const SizedBox(height: 22),
        _DoneButton(payment: payment),
      ],
    );
  }
}

class _FailedView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _FailedView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: context.colors.dangerPale, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.close_rounded, size: 28, color: context.colors.danger),
        ),
        const SizedBox(height: 16),
        Text('Payment not completed',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: context.colors.textSecondary)),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.navyStart,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Try again', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
        ),
      ],
    );
  }
}

class _DoneButton extends StatelessWidget {
  final PaymentRecord payment;
  const _DoneButton({required this.payment});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(payment),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.navyStart,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
