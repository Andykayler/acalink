import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// ─── The Acalink API ──────────────────────────────────────────────────
/// Everything this app cannot be trusted to decide for itself lives behind
/// these endpoints — which today means money, and only money.
///
/// The app can ask for a payment to be started and ask what happened to it.
/// It cannot record a payment, cannot set a price, and cannot mark anything
/// paid: those run on the server, where the answer comes from PayChangu over
/// a connection this device is not part of. See docs/payments-paychangu.md.
///
/// The base URL is a compile-time constant so a debug build can be pointed at
/// a local `vercel dev` without editing source:
///
///   flutter run --dart-define=ACALINK_API=http://10.0.2.2:3000
///
/// (10.0.2.2 is how the Android emulator reaches the host machine; a real
/// handset on the same network needs the machine's LAN address instead.)
const String apiBaseUrl = String.fromEnvironment(
  'ACALINK_API',
  defaultValue: 'https://ssp-pep.vercel.app',
);

/// Raised when the API answers with something other than success. [message]
/// is already written for a parent to read — the endpoints return plain
/// sentences rather than error codes, so it is passed through untouched.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class AcalinkApi {
  final http.Client _client;
  AcalinkApi({http.Client? client}) : _client = client ?? http.Client();

  /// The caller's Firebase ID token.
  ///
  /// A guardian session is anonymous, so the token carries no identity beyond
  /// the uid — which is exactly why the server binds a fee payment to the
  /// student it names rather than to the caller. Refreshed rather than cached:
  /// a parent can sit on the fees screen for longer than a token lives, and an
  /// expired one fails as "your session has expired" halfway through paying.
  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const ApiException('Sign in again before making a payment.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ApiException('Sign in again before making a payment.');
    }
    return token;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final token = await _idToken();
    late final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$apiBaseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // A dropped request on a Malawian mobile network is ordinary, not a
      // fault. Say so plainly rather than surfacing a socket exception.
      throw const ApiException('Could not reach Acalink. Check your connection and try again.');
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path) async {
    final token = await _idToken();
    late final http.Response res;
    try {
      res = await _client.get(
        Uri.parse('$apiBaseUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const ApiException('Could not reach Acalink. Check your connection and try again.');
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> data;
    try {
      data = res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Acalink returned an unexpected response.', res.statusCode);
    }

    if (res.statusCode >= 400) {
      throw ApiException(
        (data['error'] as String?) ?? 'Something went wrong (${res.statusCode}).',
        res.statusCode,
      );
    }
    return data;
  }
}
