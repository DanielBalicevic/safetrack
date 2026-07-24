import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_keys.dart';
import '../providers/auth_provider.dart';
import '../services/messaging_service.dart';

/// Wraps the signed-in part of the app and starts FCM once per session.
class MessagingGate extends StatefulWidget {
  const MessagingGate({super.key, required this.child});

  final Widget child;

  @override
  State<MessagingGate> createState() => _MessagingGateState();
}

class _MessagingGateState extends State<MessagingGate> {
  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid != null) {
      MessagingService.instance.init(uid, messengerKey: scaffoldMessengerKey);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
