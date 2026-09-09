import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/constellation_filters.dart';
import '../../domain/constellation_path_resolution.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/use_case/constellation_field_case.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'constellation_state.freezed.dart';

enum ConstellationViewMode {
  map,
  text,
}

@freezed
abstract class ConstellationState extends StateBase with _$ConstellationState {
  const factory ConstellationState({
    @Default(StateIsLoading()) StateStatus status,
    DateTime? loadedAt,
    ConstellationField? field,
    ConstellationPathResolution? paths,
    @Default(<String>{}) Set<String> keptPeerIds,
    @Default(false) bool capped,
    @Default(<String>{}) Set<String> filterCapabilitySlugs,
    @Default(LocationFilter.any) LocationFilter filterLocation,
    @Default(TimingFilterAny()) TimingFilter filterTiming,
    @Default(true) bool filterIncludeUnspecified,
    @Default(<String>{}) Set<String> expandedPersonIds,
    String? selectedPersonId,
    String? selectedRequestId,
    @Default(ConstellationViewMode.map) ConstellationViewMode viewMode,
    @Default(0) int graphRevision,
    Object? loadError,
  }) = _ConstellationState;

  const ConstellationState._();

  ConstellationFilters get filters => (
    capabilitySlugs: filterCapabilitySlugs,
    location: filterLocation,
    timing: filterTiming,
    includeUnspecified: filterIncludeUnspecified,
  );

  ConstellationFieldResolved? get resolvedField {
    final loadedField = field;
    final loadedPaths = paths;
    if (loadedField == null || loadedPaths == null) {
      return null;
    }
    return (
      field: loadedField,
      paths: loadedPaths,
      keptPeerIds: keptPeerIds,
      droppedHolderIds: const {},
      capped: capped,
    );
  }
}
