class FcmTestSendResult {
  const FcmTestSendResult({
    required this.ok,
    required this.devices,
    required this.sent,
    required this.mock,
    this.reason,
  });

  final bool ok;
  final int devices;
  final int sent;
  final bool mock;
  final String? reason;
}
