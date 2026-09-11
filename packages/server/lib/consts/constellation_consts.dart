/// Server-side transport guard rails for the constellation field (§5.2 / N2).
const kConstellationPeerCap = 200;
const kConstellationRequestCap = 150;

/// MeritRank context pinned for the constellation field (D14 / A2).
const kConstellationContext = '';

/// Constellation graph canvas and v1 coordinate geometry (C1).
const kConstellationCanvasExtent = 4096.0;
const kConstellationCanvasCentre = 2048.0;
const kConstellationRingUnitPixels = 170.0;
const kConstellationCoordinateMinUnits = -10.0;
const kConstellationCoordinateMaxUnits = 10.0;
const kConstellationCoordinateSpaceVersionV1 = 1;
