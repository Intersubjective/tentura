import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../constellation_anchor_composition.dart';
import '../constellation_density.dart';
import '../constellation_filters.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field.dart';
import '../port/constellation_repository_port.dart';

/// Minimum spacing between realtime-driven FULL refreshes for changes that
/// do not touch the field (see [ConstellationFieldCase.isUrgentFieldChange]).
const kLazyFieldRefreshInterval = Duration(seconds: 30);

typedef ConstellationFieldResolved = ({
  ConstellationField field,
  ConstellationComposedPresentation composition,
  ConstellationPathResolution paths,
  Set<String> keptPeerIds,
  Set<String> droppedHolderIds,
  bool capped,
});

@Order(2)
@singleton
final class ConstellationFieldCase extends UseCaseBase {
  ConstellationFieldCase(
    this._repository, {
    RealtimeSyncCase? realtimeSyncCase,
    required super.env,
    required super.logger,
  }) : _realtimeSyncCase = realtimeSyncCase;

  final ConstellationRepositoryPort _repository;
  final RealtimeSyncCase? _realtimeSyncCase;

  Stream<RealtimeEntityChange>? get changes => _realtimeSyncCase?.changesFor(
    const {
      RealtimeEntityKind.beacon,
      RealtimeEntityKind.forward,
      RealtimeEntityKind.participant,
      RealtimeEntityKind.roomMessage,
      RealtimeEntityKind.roomSeen,
    },
  );

  /// Room traffic is the high-volume kind: it only reshapes the field for a
  /// Request or Post already on it. Elsewhere it can at most revive a dormant
  /// Post, so it refreshes lazily ([kLazyFieldRefreshInterval]).
  static bool isUrgentFieldChange(
    RealtimeEntityChange change,
    Set<String> fieldBeaconIds,
  ) => switch (change.kind) {
    RealtimeEntityKind.roomMessage ||
    RealtimeEntityKind.roomSeen => fieldBeaconIds.contains(change.aggregateId),
    _ => true,
  };

  Stream<void>? get catchUps => _realtimeSyncCase?.catchUps.map((_) {});

  Future<ConstellationFieldResolved> load({
    required String viewerId,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
    ConstellationFilters localFilters = const (
      capabilitySlugs: {},
      location: LocationFilter.any,
      timing: TimingFilterAny(),
      includeUnspecified: true,
    ),
    DateTime? asOfUtc,
    ConstellationLabelBudget labelBudget = const (perPerson: 3, total: 150),
  }) async {
    final field = await _repository.fetch(
      membershipFilters: membershipFilters,
      projection: projection,
    );
    final loadedAt = asOfUtc ?? field.loadedAt;
    final composition = composeConstellationPresentation(
      viewerId: viewerId,
      field: field,
      localFilters: localFilters,
      asOfUtc: loadedAt,
      labelBudget: labelBudget,
    );

    return (
      field: field,
      composition: composition,
      paths: composition.paths,
      keptPeerIds: composition.keptPeerIds,
      droppedHolderIds: composition.droppedHolderIds,
      capped: composition.renderBudgetCapped,
    );
  }
}
