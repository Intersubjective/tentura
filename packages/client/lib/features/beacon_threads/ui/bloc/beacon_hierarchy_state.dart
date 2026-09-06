import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_hierarchy_state.freezed.dart';

@freezed
abstract class BeaconHierarchyGroupSlice with _$BeaconHierarchyGroupSlice {
  const factory BeaconHierarchyGroupSlice({
    @Default([]) List<BeaconHierarchySummary> items,
    String? nextCursor,
    @Default(false) bool loading,
    @Default(false) bool loadingMore,
    Object? error,
    @Default(false) bool expanded,
  }) = _BeaconHierarchyGroupSlice;

  const BeaconHierarchyGroupSlice._();

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

@freezed
abstract class BeaconHierarchyState extends StateBase with _$BeaconHierarchyState {
  const factory BeaconHierarchyState({
    BeaconHierarchyCapabilities? capabilities,
    BeaconParentReference? parentReference,
    @Default(BeaconHierarchyGroupSlice()) BeaconHierarchyGroupSlice active,
    @Default(BeaconHierarchyGroupSlice()) BeaconHierarchyGroupSlice finished,
    @Default(
      BeaconHierarchyGroupSlice(expanded: false),
    )
    BeaconHierarchyGroupSlice deleted,
    @Default(StateIsSuccess()) StateStatus status,
    Object? capabilitiesError,
    @Default(false) bool parentReferenceLoading,
    Object? parentReferenceError,
  }) = _BeaconHierarchyState;

  const BeaconHierarchyState._();

  bool get hasCapabilities => capabilities != null;

  bool get canListChildren => capabilities?.canListChildren ?? false;

  bool get canCreateChild => capabilities?.canCreateChild ?? false;

  BeaconHierarchyGroupSlice sliceFor(BeaconHierarchyChildGroup group) =>
      switch (group) {
        BeaconHierarchyChildGroup.active => active,
        BeaconHierarchyChildGroup.finished => finished,
        BeaconHierarchyChildGroup.deleted => deleted,
      };
}
