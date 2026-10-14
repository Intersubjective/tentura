import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/fcm_cubit.dart';
import '../bloc/fcm_state.dart';

/// Notification settings row for this device's permission. Offers "Turn on"
/// while nobody has asked yet (also after the home banner was closed), and
/// points to the browser's site settings once notifications are blocked.
/// Shows nothing when granted or unsupported.
class NotificationPermissionDeviceTile extends StatelessWidget {
  const NotificationPermissionDeviceTile({
    this.cubit,
    super.key,
  });

  /// Defaults to the global [FcmCubit].
  final FcmCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final fcmCubit =
        cubit ??
        (GetIt.I.isRegistered<FcmCubit>() ? GetIt.I<FcmCubit>() : null);
    if (fcmCubit == null) return const SizedBox.shrink();
    return BlocBuilder<FcmCubit, FcmState>(
      bloc: fcmCubit,
      buildWhen: (p, c) => p.permissionStatus != c.permissionStatus,
      builder: (context, state) {
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        return switch (state.permissionStatus) {
          NotificationPermissionStatus.notDetermined => ListTile(
            leading: Icon(Icons.notifications_outlined, color: tt.info),
            title: Text(l10n.notificationPermissionDeviceTitle),
            subtitle: Text(l10n.notificationPermissionDeviceOff),
            trailing: TenturaTextAction(
              label: l10n.notificationPromptAllow,
              onPressed: () =>
                  unawaited(fcmCubit.requestPermissionFromUser()),
              semanticsIdentifier: 'notification-permission-allow',
            ),
          ),
          NotificationPermissionStatus.denied => ListTile(
            leading: Icon(Icons.notifications_off_outlined, color: tt.warn),
            title: Text(l10n.notificationPermissionDeviceTitle),
            subtitle: Text(l10n.notificationPermissionBlocked),
          ),
          NotificationPermissionStatus.granted ||
          NotificationPermissionStatus.unsupported => const SizedBox.shrink(),
        };
      },
    );
  }
}
