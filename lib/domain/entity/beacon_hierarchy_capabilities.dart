import 'beacon_hierarchy_denial_code.dart';

/// Whether the viewer may list or create children on a parent request.
class BeaconHierarchyCapabilities {
  const BeaconHierarchyCapabilities({
    required this.canListChildren,
    required this.canCreateChild,
    this.denialCode,
  });

  final bool canListChildren;
  final bool canCreateChild;
  final BeaconHierarchyDenialCode? denialCode;
}
