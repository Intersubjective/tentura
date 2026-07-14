import 'package:injectable/injectable.dart';

import 'package:tentura/features/notification/domain/port/direct_notification_probe_port.dart';

import 'direct_notification_probe.dart';

@LazySingleton(as: DirectNotificationProbePort)
final class DirectNotificationProbeAdapter
    implements DirectNotificationProbePort {
  @override
  Future<void> show() => showDirectTestNotification();
}
