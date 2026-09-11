import 'package:tentura_server/domain/entity/constellation_anchor.dart';

/// Account watermark after an anchor mutation (C3).
class ConstellationAnchorWatermark {
  const ConstellationAnchorWatermark(this.revision);

  final ConstellationAnchorRevision revision;
}

class ConstellationAnchorUpsertResult {
  const ConstellationAnchorUpsertResult({
    required this.anchor,
    required this.watermark,
  });

  final ConstellationAnchor anchor;
  final ConstellationAnchorWatermark watermark;
}

class ConstellationAnchorDeleteResult {
  const ConstellationAnchorDeleteResult({
    required this.target,
    required this.watermark,
  });

  final ConstellationAnchorTarget target;
  final ConstellationAnchorWatermark watermark;
}

abstract interface class ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorUpsertResult> upsertAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  });

  Future<ConstellationAnchorDeleteResult> deleteAnchor({
    required String viewerId,
    required ConstellationAnchorTarget target,
  });

  /// Read-only cursor revision; returns revision zero when no cursor row exists.
  Future<ConstellationAnchorRevision> readWatermark(String viewerId);
}
