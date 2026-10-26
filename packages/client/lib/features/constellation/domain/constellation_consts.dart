import 'package:tentura/consts.dart';

export 'package:tentura_root/domain/constellation/constellation_geometry.dart';

/// Client-side render budget for path-preserving peer selection (§5.2 / N2).
///
/// Must stay strictly below `kConstellationPeerCap` on the server (200).
const kConstellationRenderPeerCap = 120;

/// Render budget with semantic zoom (`kFieldSemanticZoomEnabled`): the close /
/// district / overview levels keep a 400-person map readable. Equals the
/// server peer cap (400).
const kConstellationRenderPeerCapSemanticZoom = 400;

/// The render budget for the given semantic-zoom setting.
int constellationRenderPeerCap({
  bool semanticZoomEnabled = kFieldSemanticZoomEnabled,
}) => semanticZoomEnabled
    ? kConstellationRenderPeerCapSemanticZoom
    : kConstellationRenderPeerCap;
