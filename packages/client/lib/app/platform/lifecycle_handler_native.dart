import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';

class LifecycleHandler extends StatefulWidget {
  const LifecycleHandler({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler> {
  final _appLifecycleListener = AppLifecycleListener();

  @override
  void initState() {
    super.initState();
    _appLifecycleListener.hashCode;
    unawaited(_attachFcmNotificationRouting());
  }

  Future<void> _attachFcmNotificationRouting() async {
    try {
      final router = GetIt.I<RootRouter>();
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final link = m.data['link'] as String?;
        if (link == null || link.isEmpty) {
          return;
        }
        unawaited(router.openFromNotificationLink(link));
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      final il = initial?.data['link'] as String?;
      if (il != null && il.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(router.openFromNotificationLink(il));
        });
      }
    } catch (_) {
      // Firebase not wired (tests, desktop, or missing config).
    }
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
