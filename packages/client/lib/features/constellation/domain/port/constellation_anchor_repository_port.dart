import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

part 'constellation_anchor_repository_port.freezed.dart';

@freezed
abstract class ConstellationAnchorUpsertResult
    with _$ConstellationAnchorUpsertResult {
  const factory ConstellationAnchorUpsertResult({
    required ConstellationAnchor anchor,
    required ConstellationAnchorRevision revision,
  }) = _ConstellationAnchorUpsertResult;
}

@freezed
abstract class ConstellationAnchorDeleteResult
    with _$ConstellationAnchorDeleteResult {
  const factory ConstellationAnchorDeleteResult({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorRevision revision,
  }) = _ConstellationAnchorDeleteResult;
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
