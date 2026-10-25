import 'dart:io' show Platform;

/// The platform this app runs on, as a sign-in method's device label (#467).
String? currentDeviceLabel() {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  return null;
}
