class EmailTestSendResult {
  const EmailTestSendResult({
    required this.ok,
    required this.mock,
    this.reason,
  });

  final bool ok;
  final bool mock;
  final String? reason;
}
