import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../models/student.dart';

/// ─── Paying by mobile money, for real ─────────────────────────────────
///
/// The old flow in this app wrote a payment straight to Firestore and showed
/// the parent a receipt number. Nothing had checked the money arrived — the
/// balance dropped on the strength of a number typed into a text field, and
/// the row landed in the bursar's ledger looking like every other receipt.
/// That is the hole the PAYMENT INTEGRITY note in firestore.rules describes.
///
/// This is the replacement. The app asks the server to open a PayChangu
/// checkout, sends the payer there in their own browser, and then asks the
/// server what happened. Nothing here decides anything: the receipt exists
/// only once PayChangu has confirmed the payment to our own backend, over a
/// connection this handset is not part of.
///
/// What the app gains, beyond honesty: the payer never types a PIN or a card
/// number into Acalink, so nothing sensitive passes through this code at all.

/// The state a checkout can be in, as the server reports it.
enum PaymentPhase { pending, success, failed }

class PaymentStatus {
  final String txRef;
  final PaymentPhase phase;
  final int amount;
  final String? receiptNo;
  final String? studentName;

  const PaymentStatus({
    required this.txRef,
    required this.phase,
    required this.amount,
    this.receiptNo,
    this.studentName,
  });

  factory PaymentStatus.fromJson(Map<String, dynamic> json) {
    final raw = (json['status'] as String?) ?? 'pending';
    return PaymentStatus(
      txRef: (json['txRef'] as String?) ?? '',
      phase: switch (raw) {
        'success' => PaymentPhase.success,
        // 'underpaid' is a discrepancy for a human at Acalink to unpick, not
        // something to show a parent as a half-success. It reads as failed
        // here and the server keeps the detail.
        'failed' || 'cancelled' || 'underpaid' => PaymentPhase.failed,
        _ => PaymentPhase.pending,
      },
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      receiptNo: json['receiptNo'] as String?,
      studentName: json['studentName'] as String?,
    );
  }
}

/// What [PayChanguService.startCheckout] hands back: where to send the payer,
/// and the reference to watch afterwards.
class Checkout {
  final String txRef;
  final String checkoutUrl;

  /// What the student's account is credited with — the amount the parent chose.
  final int amount;

  /// The processing fee added on top, and so what the parent is actually
  /// charged. Zero when the server did not say; see [total].
  final int fee;

  /// Set for an in-app mobile money charge ('airtel' | 'tnm') and the number
  /// the prompt went to; empty for a hosted checkout.
  final String network;
  final String mobile;

  const Checkout({
    required this.txRef,
    required this.checkoutUrl,
    required this.amount,
    this.fee = 0,
    this.network = '',
    this.mobile = '',
  });

  bool get inApp => checkoutUrl.isEmpty;

  /// What PayChangu will take from the parent.
  int get total => amount + fee;
}

class PayChanguService {
  final AcalinkApi _api;
  PayChanguService({AcalinkApi? api}) : _api = api ?? AcalinkApi();

  /// Opens a checkout for a fee payment.
  ///
  /// [amount] is honoured — part-payment against a balance is how school fees
  /// are actually paid here. It can only ever under-promise: the school is
  /// credited with what PayChangu confirms was received, never with what this
  /// app said.
  Future<Checkout> startCheckout({
    required Student student,
    required int amount,
    required String term,
    String payerName = '',
    String payerPhone = '',
    String payerEmail = '',
    String academicYear = '',
    String note = '',
  }) async {
    final data = await _api.post('/api/payments/initiate', {
      'purpose': 'school_fee',
      'studentId': student.id,
      'amount': amount,
      'term': term,
      'academicYear': academicYear,
      'payerName': payerName.isNotEmpty ? payerName : student.guardianName,
      'payerPhone': payerPhone.isNotEmpty ? payerPhone : student.guardianPhone,
      'payerEmail': payerEmail.isNotEmpty ? payerEmail : student.guardianEmail,
      'note': note,
    });

    final url = data['checkoutUrl'] as String?;
    final ref = data['txRef'] as String?;
    if (url == null || ref == null) {
      throw const ApiException('Acalink could not start the payment. Try again shortly.');
    }

    return Checkout(
      txRef: ref,
      checkoutUrl: url,
      amount: (data['amount'] as num?)?.toInt() ?? amount,
      fee: (data['fee'] as num?)?.toInt() ?? 0,
    );
  }

  /// Charges a mobile money wallet without leaving the app: PayChangu pushes a
  /// PIN prompt to [mobile] and the caller waits on [watch]. The returned
  /// [Checkout] has an empty `checkoutUrl` — there is no page to visit.
  Future<Checkout> startMobileMoney({
    required Student student,
    required int amount,
    required String term,
    required String network, // 'airtel' | 'tnm'
    required String mobile,
    String payerName = '',
    String academicYear = '',
  }) async {
    final data = await _api.post('/api/payments/initiate', {
      'purpose': 'school_fee',
      'method': 'mobile_money',
      'network': network,
      'mobile': mobile,
      'studentId': student.id,
      'amount': amount,
      'term': term,
      'academicYear': academicYear,
      'payerName': payerName.isNotEmpty ? payerName : student.guardianName,
      'payerPhone': mobile,
      'payerEmail': student.guardianEmail,
    });
    final ref = data['txRef'] as String?;
    if (ref == null) {
      throw const ApiException('Acalink could not start the payment. Try again shortly.');
    }
    return Checkout(
      txRef: ref,
      checkoutUrl: '',
      amount: (data['amount'] as num?)?.toInt() ?? amount,
      fee: (data['fee'] as num?)?.toInt() ?? 0,
      network: network,
      mobile: mobile,
    );
  }

  /// Sends the payer to PayChangu in the device's own browser.
  ///
  /// Deliberately an external application rather than an in-app webview: the
  /// payer should be able to see the address bar and the padlock on the page
  /// where they approve money leaving their account. It also means an Airtel
  /// or Mpamba deep link can be handled by the app that owns it.
  Future<bool> openCheckout(String checkoutUrl) {
    return launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
  }

  Future<PaymentStatus> checkStatus(String txRef) async {
    final data = await _api.get('/api/payments/status?tx_ref=$txRef');
    return PaymentStatus.fromJson(data);
  }

  /// Watches a transaction until it resolves, or until [timeout].
  ///
  /// Backs off from two seconds to ten. A mobile-money payment involves the
  /// payer finding their handset and entering a PIN, which takes as long as it
  /// takes; polling every two seconds for four minutes would be a hundred
  /// needless requests over a connection that is often metered.
  ///
  /// A dropped request is not a failed payment — the money may already be
  /// moving — so a network error is reported through [onTransientError] and
  /// the watch continues. Cancel the returned subscription when the sheet
  /// closes; settlement happens on the server whether or not anyone is
  /// watching.
  Stream<PaymentStatus> watch(
    String txRef, {
    Duration timeout = const Duration(minutes: 15),
    void Function(Object error)? onTransientError,
  }) async* {
    var delay = const Duration(seconds: 2);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await checkStatus(txRef);
        yield status;
        if (status.phase != PaymentPhase.pending) return;
      } catch (e) {
        onTransientError?.call(e);
      }

      await Future<void>.delayed(delay);
      final next = (delay.inMilliseconds * 1.4).round();
      delay = Duration(milliseconds: next > 10000 ? 10000 : next);
    }
  }
}
