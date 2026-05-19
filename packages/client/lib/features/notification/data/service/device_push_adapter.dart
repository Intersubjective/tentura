import 'package:injectable/injectable.dart';

import 'package:tentura/domain/port/device_push_port.dart';

import '../../domain/use_case/fcm_case.dart';

@Singleton(
  as: DevicePushPort,
  env: [Environment.dev, Environment.prod],
)
class DevicePushAdapter implements DevicePushPort {
  DevicePushAdapter(this._fcmCase);

  final FcmCase _fcmCase;

  @override
  Future<void> unregisterCurrentDevice() =>
      _fcmCase.unregisterCurrentDevice();
}
