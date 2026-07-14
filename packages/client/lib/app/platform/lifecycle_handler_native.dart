import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/platform/orientation_policy.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

class LifecycleHandler extends StatefulWidget {
  const LifecycleHandler({
    required this.child,
    this.attachNotificationRouting = true,
    super.key,
  });

  final Widget child;
  final bool attachNotificationRouting;

  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.attachNotificationRouting) {
      unawaited(_attachFcmNotificationRouting());
    }
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return;
    }
    unawaited(applyOrientationPolicyForView(views.first));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    GetIt.I<RealtimeSyncCase>().requestCatchUp(
      RealtimeCatchUpReason.appResumed,
    );
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
