import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_filters.dart';
import '../../domain/constellation_path_resolution.dart';
import '../../domain/entity/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/use_case/constellation_field_case.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'constellation_state.freezed.dart';

enum ConstellationViewMode {
  map,
  text,
}

enum ConstellationPlacementPhase {
  idle,
  draggingExisting,
  draggingNew,
}

@freezed
abstract class ConstellationState extends StateBase with _$ConstellationState {
  const factory ConstellationState({
    @Default(StateIsLoading()) StateStatus status,
    DateTime? loadedAt,
    ConstellationField? field,
    ConstellationComposedPresentation? composition,
    ConstellationPathResolution? paths,
    @Default(<String>{}) Set<String> keptPeerIds,
    @Default(false) bool capped,
    @Default(<String>{}) Set<String> filterCapabilitySlugs,
    @Default(LocationFilter.any) LocationFilter filterLocation,
    @Default(TimingFilterAny()) TimingFilter filterTiming,
    @Default(true) bool filterIncludeUnspecified,
    @Default(ConstellationFieldMembershipFilters.defaults)
    ConstellationFieldMembershipFilters membershipFilters,
    @Default(<String>{}) Set<String> expandedPersonIds,
    String? selectedPersonId,
    String? selectedRequestId,
    @Default(ConstellationViewMode.map) ConstellationViewMode viewMode,
    @Default(0) int graphRevision,
    Object? loadError,
    @Default(0) int loadGeneration,
    @Default(ConstellationPlacementPhase.idle)
    ConstellationPlacementPhase placementPhase,
    ConstellationAnchorTarget? activePlacementTarget,
    @Default(<ConstellationAnchorTarget>{})
    Set<ConstellationAnchorTarget> deferredRefreshTargets,
    String? placementFailureMessage,
    String? graphLayoutFailureMessage,
    @Default(false) bool syncPending,
    @Default(false) bool placementActionsEnabled,
  }) = _ConstellationState;

  const ConstellationState._();

  ConstellationFilters get filters => (
    capabilitySlugs: filterCapabilitySlugs,
    location: filterLocation,
    timing: filterTiming,
    includeUnspecified: filterIncludeUnspecified,
  );

  ConstellationAnchorProjection? get confirmedProjection =>
      field?.resolvedAnchorProjection;

  bool get hasPendingPlacementWrite =>
      placementPhase == ConstellationPlacementPhase.draggingExisting ||
      placementPhase == ConstellationPlacementPhase.draggingNew;

  ConstellationFieldResolved? get resolvedField {
    final loadedField = field;
    final loadedPaths = paths;
    final loadedComposition = composition;
    if (loadedField == null || loadedPaths == null || loadedComposition == null) {
      return null;
    }
    return (
      field: loadedField,
      composition: loadedComposition,
      paths: loadedPaths,
      keptPeerIds: keptPeerIds,
      droppedHolderIds: loadedComposition.droppedHolderIds,
      capped: capped,
    );
  }
}
