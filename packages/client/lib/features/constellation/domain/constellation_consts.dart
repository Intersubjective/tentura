/// Client-side render budget for path-preserving peer selection (§5.2 / N2).
///
/// Must stay strictly below [kConstellationPeerCap] on the server (200).
const kConstellationRenderPeerCap = 120;
