/// Client-side render budget for path-preserving peer selection (§5.2 / N2).
///
/// Must stay strictly below [kConstellationPeerCap] on the server (200).
const kConstellationRenderPeerCap = 120;

/// Constellation graph canvas and v1 coordinate geometry (C1).
const kConstellationCanvasExtent = 4096.0;
const kConstellationCanvasCentre = 2048.0;
const kConstellationRingUnitPixels = 170.0;
const kConstellationCoordinateMinUnits = -10.0;
const kConstellationCoordinateMaxUnits = 10.0;
const kConstellationCoordinateSpaceVersionV1 = 1;
