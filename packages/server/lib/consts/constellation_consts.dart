export 'package:tentura_root/domain/constellation/constellation_geometry.dart';

/// Server-side transport guard rails for the constellation field (§5.2 / N2).
const kConstellationPeerCap = 200;
const kConstellationRequestCap = 150;

/// Max characters of a Post's root message shown on its field card.
const kConstellationPostExcerptLength = 140;

/// MeritRank context pinned for the constellation field (D14 / A2).
const kConstellationContext = '';
