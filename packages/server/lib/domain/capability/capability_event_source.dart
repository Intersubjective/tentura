enum CapabilityEventSource {
  privateLabel(0),
  forwardReason(1),
  commitRole(2),
  closeAcknowledgement(3);

  const CapabilityEventSource(this.dbValue);

  final int dbValue;

  static CapabilityEventSource fromDbValue(int v) =>
      values.firstWhere((e) => e.dbValue == v);
}
