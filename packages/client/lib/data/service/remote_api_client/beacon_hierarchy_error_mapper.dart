import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';

/// Throws the matching [BeaconHierarchyException] for a recognized nested-
/// request GraphQL error [code] (plan §3.5). Returns normally (no throw) for
/// any other code, so the caller falls through to its generic mapping.
void throwIfBeaconHierarchyError(int? code, Map<String, dynamic>? extensions) {
  switch (code) {
    case BeaconChildCreateForbiddenException.codeNumber:
      throw const BeaconChildCreateForbiddenException();
    case BeaconParentNotCoordinatableException.codeNumber:
      throw const BeaconParentNotCoordinatableException();
    case BeaconPromotionSourceInvalidException.codeNumber:
      throw const BeaconPromotionSourceInvalidException();
    case BeaconSourceAlreadyPromotedException.codeNumber:
      throw BeaconSourceAlreadyPromotedException(
        existingChildBeaconId: extensions?['beaconId'] as String?,
      );
    case BeaconChildCommandConflictException.codeNumber:
      throw const BeaconChildCommandConflictException();
    case BeaconChildCommandGoneException.codeNumber:
      throw const BeaconChildCommandGoneException();
    case DiscussionScopeDisabledException.codeNumber:
      throw const DiscussionScopeDisabledException();
    case CoordinationKindDisabledException.codeNumber:
      throw const CoordinationKindDisabledException();
    case BeaconHierarchyCursorInvalidException.codeNumber:
      throw const BeaconHierarchyCursorInvalidException();
  }
}
