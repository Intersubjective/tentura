import 'package:meta/meta.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_field.dart';

/// What the constellation store currently holds for one account generation.
@immutable
final class ConstellationFieldStoreState {
  const ConstellationFieldStoreState({
    required this.field,
    required this.coveredRevision,
    required this.generation,
  });

  /// Newest applied FULL, with the newest complete anchor projection.
  final ConstellationField? field;

  /// Revision of the newest complete anchor projection held.
  final ConstellationAnchorRevision coveredRevision;

  /// Changes only on account replacement or logout.
  final int generation;
}
