part of '_migrations.dart';

/// Widens the Field placement range from ±10 to ±40 units per axis (#968).
///
/// The bound equals `kConstellationCoordinateMaxUnits` (shared geometry);
/// it is written out here because a shipped migration must never change.
/// NaN and ±Infinity stay rejected: both fall outside any finite range.
final m0298 = Migration('0298', [
  '''
ALTER TABLE public.constellation_anchor
  DROP CONSTRAINT IF EXISTS constellation_anchor__coord_chk
''',
  '''
ALTER TABLE public.constellation_anchor
  ADD CONSTRAINT constellation_anchor__coord_chk CHECK (
    coordinate_space_version = 1
    AND x_units >= -40 AND x_units <= 40
    AND y_units >= -40 AND y_units <= 40
  )
''',
]);
