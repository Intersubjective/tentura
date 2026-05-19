/// Device-scoped push registration (implemented by notification feature).
abstract class DevicePushPort {
  Future<void> unregisterCurrentDevice();
}
