import '../../domain/exception/beacon_plan_exceptions.dart';

/// Throws the matching [BeaconPlanException] for a recognized plan GraphQL
/// error [code]. Returns normally for any other code.
void throwIfBeaconPlanError(int? code, Map<String, dynamic>? extensions) {
  switch (code) {
    case PlanEditConflictException.codeNumber:
      final rawSeq = extensions?['currentSeq'];
      final rawIds = extensions?['conflictStepIds'];
      throw PlanEditConflictException(
        currentSeq: switch (rawSeq) {
          final int v => v,
          final num v => v.toInt(),
          final String v => int.tryParse(v) ?? 0,
          _ => 0,
        },
        conflictStepIds: rawIds is List
            ? [
                for (final id in rawIds)
                  if (id is String && id.isNotEmpty) id,
              ]
            : const [],
      );
    case PlanStepNotFoundException.codeNumber:
      throw const PlanStepNotFoundException();
    case PlanNotEditableException.codeNumber:
      throw const PlanNotEditableException();
    case PlanActionStaleException.codeNumber:
      throw const PlanActionStaleException();
    case PlanRestoreSourceMissingException.codeNumber:
      throw const PlanRestoreSourceMissingException();
    case PlanRateLimitedException.codeNumber:
      throw const PlanRateLimitedException();
    case PlanAssigneeNotAdmittedException.codeNumber:
      throw const PlanAssigneeNotAdmittedException();
    case PlanTooLargeException.codeNumber:
      throw const PlanTooLargeException();
    case PlanDisabledException.codeNumber:
      throw const PlanDisabledException();
    case PlanInvalidException.codeNumber:
      throw const PlanInvalidException();
  }
}
