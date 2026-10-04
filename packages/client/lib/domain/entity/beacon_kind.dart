/// `beacon.kind` smallint.
enum BeaconKind {
  request(0),
  post(1)
  ;

  const BeaconKind(this.value);

  final int value;

  static BeaconKind fromValue(int v) => values.singleWhere(
    (e) => e.value == v,
    orElse: () => throw ArgumentError.value(v, 'v', 'Unknown beacon kind'),
  );
}

/// `beacon.forward_policy` smallint.
enum BeaconForwardPolicyValue {
  closed(0),
  open(1)
  ;

  const BeaconForwardPolicyValue(this.value);

  final int value;

  static BeaconForwardPolicyValue fromValue(int v) => values.singleWhere(
    (e) => e.value == v,
    orElse: () => throw ArgumentError.value(v, 'v', 'Unknown forward policy'),
  );
}
