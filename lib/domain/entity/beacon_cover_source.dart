/// Persisted `beacon.cover_source` wire values (smallint).
enum BeaconCoverSource {
  photo(0),
  symbol(1);

  const BeaconCoverSource(this.wireValue);

  final int wireValue;

  /// Strict parse for command paths; rejects unknown values.
  static BeaconCoverSource parse(int value) => switch (value) {
        0 => photo,
        1 => symbol,
        _ => throw ArgumentError.value(value, 'value', 'unknown cover source'),
      };

  /// Tolerant read mapping: unknown/null → photo.
  static BeaconCoverSource fromWireOrPhoto(int? value) => switch (value) {
        1 => symbol,
        _ => photo,
      };
}
