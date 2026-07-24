import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// FCM push notifications. Requests permission, stores the token in
/// `users/{uid}.fcmToken` for the Cloud Functions, and shows foreground
/// messages as a SnackBar. On the simulator there is no APNs token, so
/// `getToken()` may fail; the rest of the app keeps working.
class MessagingService {
  MessagingService._();
  static final instance = MessagingService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  bool _listenersReady = false;
  String? _uid;

  /// Called after sign-in.
  Future<void> init(
    String uid, {
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) async {
    _uid = uid;

    await _fm.requestPermission(alert: true, badge: true, sound: true);

    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    try {
      final token = await _fm.getToken();
      if (token != null) await _writeToken(uid, token);
    } catch (_) {
      // No APNs token (e.g. simulator).
    }

    // Registered once; they always use the current _uid.
    if (!_listenersReady) {
      _listenersReady = true;
      _fm.onTokenRefresh.listen((t) {
        final u = _uid;
        if (u != null) _writeToken(u, t);
      });
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        final state = messengerKey?.currentState;
        if (n == null || state == null) return;
        state.showSnackBar(
          SnackBar(
            backgroundColor: state.context.colors.primaryContainer,
            content: Text(
              n.title != null ? '${n.title}: ${n.body ?? ''}' : (n.body ?? 'New alert'),
            ),
          ),
        );
      });
    }
  }

  Future<void> _writeToken(String uid, String token) {
    return FirebaseFirestore.instance.doc('users/$uid').set(
      {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Removes the token on sign-out so the user stops receiving push.
  Future<void> clearToken(String uid) async {
    _uid = null;
    try {
      await FirebaseFirestore.instance.doc('users/$uid').set(
        {'fcmToken': FieldValue.delete()},
        SetOptions(merge: true),
      );
      await _fm.deleteToken();
    } catch (_) {
      // Best effort: must not block sign-out.
    }
  }
}
