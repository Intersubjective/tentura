export 'package:tentura_root/domain/constellation/constellation_geometry.dart';

/// Server-side transport guard rails for the constellation field (§5.2 / N2).
const kConstellationPeerCap = 400;
const kConstellationRequestCap = 150;

/// Most operations one `constellationAnchorsApply` batch may hold.
const kConstellationAnchorBatchCap = 400;

/// Candidates examined per readability batch of the discoverable keyset scan.
const kConstellationDiscoverableScanBatch = kConstellationRequestCap + 1;

/// Most Requests one targeted `constellationFieldRequests` read returns
/// (#671); the client asks for the few a burst of hints named.
const kConstellationFieldRequestsByIdsCap = 20;

/// Max characters of a Post's root message shown on its field card.
const kConstellationPostExcerptLength = 140;

/// MeritRank context pinned for the constellation field (D14 / A2).
const kConstellationContext = '';
