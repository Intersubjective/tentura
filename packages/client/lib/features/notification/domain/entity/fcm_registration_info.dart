class FcmRegistrationInfo {
  const FcmRegistrationInfo({
    required this.token,
    required this.appId,
    required this.platform,
    required this.permissionGranted,
    required this.serverSynced,
  });

  final String? token;
  final String? appId;
  final String platform;
  final bool permissionGranted;
  final bool serverSynced;
}
