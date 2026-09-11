import '../entity/constellation_anchor.dart';

class ConstellationAnchorUpsertResult {
  const ConstellationAnchorUpsertResult({
    required this.anchor,
    required this.revision,
  });

  final ConstellationAnchor anchor;
  final ConstellationAnchorRevision revision;
}

class ConstellationAnchorDeleteResult {
  const ConstellationAnchorDeleteResult({
    required this.target,
    required this.revision,
  });

  final ConstellationAnchorTarget target;
  final ConstellationAnchorRevision revision;
}

abstract interface class ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  });

  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  });
}
