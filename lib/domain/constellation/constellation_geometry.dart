/// Constellation graph canvas and v1 coordinate geometry (C1).
///
/// Field canvas is square; centre is always half the extent (issue #968).
const kConstellationCanvasExtent = 16384.0;
const kConstellationCanvasCentre = kConstellationCanvasExtent / 2;
const kConstellationRingUnitPixels = 170.0;

/// Placement range per axis in v1 units (issue #968: 4× the old ±10 per
/// side). The database CHECK `constellation_anchor__coord_chk` (m0298) uses
/// the same bound; widening it again needs a new migration.
const kConstellationCoordinateMaxUnits = 40.0;
const kConstellationCoordinateMinUnits = -kConstellationCoordinateMaxUnits;
const kConstellationCoordinateSpaceVersionV1 = 1;
