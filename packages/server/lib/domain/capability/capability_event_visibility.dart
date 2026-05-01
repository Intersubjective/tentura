enum CapabilityEventVisibility {
  private(0),
  beaconScoped(1);

  const CapabilityEventVisibility(this.dbValue);

  final int dbValue;
}
