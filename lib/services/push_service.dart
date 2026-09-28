import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'notifications_service.dart';

/// Device-side half of push notifications.
///
/// Firestore is still the source of truth: the web portals write a
/// `notifications` document, and a trusted worker (scripts/push-worker.js)
/// turns it into an FCM message. All this class does is make sure the school
/// knows where to send it, and react when one arrives.
///
/// A device registration lives in `parent_devices/{token}` rather than on the
/// student, because one phone can belong to a guardian with several children
/// and the same guardian may use two phones.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _registeredPhone;
  String? _token;
  bool _listenersAttached = false;

  /// Called from a notification tap so the app can jump to the right screen.
  /// Set by the widget tree; null until then.
  void Function(RemoteMessage message)? onNotificationTap;

  /// Called when a push arrives while the app is in the foreground. Android
  /// does NOT raise a system notification in that case — the app is expected
  /// to surface it — so the UI shows an in-app banner instead.
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Asks for permission, registers this device against [phone], and wires up
  /// the message listeners. Safe to call on every login and session restore;
  /// it re-registers only when the guardian actually changes.
  Future<void> register(String phone) async {
    if (phone.isEmpty) return;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] permission denied — notifications stay in-app only');
        return;
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('[push] no FCM token available on this device');
        return;
      }

      if (_registeredPhone != phone || _token != token) {
        await _saveToken(token, phone);
        _registeredPhone = phone;
        _token = token;
      }

      // A token can be rotated by the OS at any time; if we miss that, the
      // school keeps pushing into a dead address.
      _messaging.onTokenRefresh.listen((fresh) {
        _token = fresh;
        if (_registeredPhone != null) _saveToken(fresh, _registeredPhone!);
      });

      _attachListeners();
    } catch (e) {
      // Push is an enhancement — never let it break sign-in.
      debugPrint('[push] registration failed: $e');
    }
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.onMessage.listen((message) {
      onForegroundMessage?.call(message);
    });

    // Tapped while the app was backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(message);
    });
  }

  /// A tap that launched the app from a terminated state arrives here instead
  /// of through onMessageOpenedApp, so the caller has to ask for it once.
  Future<RemoteMessage?> initialMessage() => _messaging.getInitialMessage();

  Future<void> _saveToken(String token, String phone) async {
    final parentId = parentRecipientId(phone);
    try {
      await _firestore.collection('parent_devices').doc(token).set({
        'token': token,
        'parentId': parentId,
        'phone': phone,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      debugPrint('[push] device registered for $parentId');
    } catch (e) {
      debugPrint('[push] could not save token: $e');
    }
  }

  /// Removes this device on logout so a shared phone stops receiving another
  /// family's notifications.
  Future<void> unregister() async {
    final token = _token;
    _registeredPhone = null;
    _token = null;
    if (token == null) return;
    try {
      await _firestore.collection('parent_devices').doc(token).delete();
    } catch (e) {
      debugPrint('[push] could not remove token: $e');
    }
  }
}
