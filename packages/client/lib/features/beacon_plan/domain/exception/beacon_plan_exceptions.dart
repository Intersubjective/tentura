/// Typed translations of the Request plan («либретто», #220) GraphQL error
/// codes 1336–1346 (server plan and poll validation errors).
///
/// Thrown by `throwIfBeaconPlanError` (in
/// `data/model/beacon_plan_error_mapper.dart`) from the routing link's
/// `onGraphQLError` handler when it recognizes one of these codes in a
/// GraphQL error's `extensions.code`.
sealed class BeaconPlanException implements Exception {
  const BeaconPlanException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? 'BeaconPlanException';
}

/// The save/restore base is stale. [currentSeq] is the plan head now;
/// [conflictStepIds] are the steps both sides changed (empty when a restore
/// simply lost the race).
final class PlanEditConflictException extends BeaconPlanException {
  const PlanEditConflictException({
    required this.currentSeq,
    this.conflictStepIds = const [],
  });

  static const codeNumber = 1336;

  final int currentSeq;

  final List<String> conflictStepIds;
}

/// The step does not exist (any more).
final class PlanStepNotFoundException extends BeaconPlanException {
  const PlanStepNotFoundException([super.message]);

  static const codeNumber = 1337;
}

/// The Request is not in a state that allows plan writes.
final class PlanNotEditableException extends BeaconPlanException {
  const PlanNotEditableException([super.message]);

  static const codeNumber = 1338;
}

/// A one-tap action refers to a state that has moved on.
final class PlanActionStaleException extends BeaconPlanException {
  const PlanActionStaleException([super.message]);

  static const codeNumber = 1339;
}

/// The revision to restore is gone.
final class PlanRestoreSourceMissingException extends BeaconPlanException {
  const PlanRestoreSourceMissingException([super.message]);

  static const codeNumber = 1340;
}

/// Too many plan writes in a row.
final class PlanRateLimitedException extends BeaconPlanException {
  const PlanRateLimitedException([super.message]);

  static const codeNumber = 1341;
}

/// A step was assigned to someone who is not admitted to the Request.
final class PlanAssigneeNotAdmittedException extends BeaconPlanException {
  const PlanAssigneeNotAdmittedException([super.message]);

  static const codeNumber = 1342;
}

/// The plan exceeds its limits (steps, field lengths).
final class PlanTooLargeException extends BeaconPlanException {
  const PlanTooLargeException([super.message]);

  static const codeNumber = 1343;
}

/// Plans are switched off on the server.
final class PlanDisabledException extends BeaconPlanException {
  const PlanDisabledException([super.message]);

  static const codeNumber = 1344;
}

/// The plan draft is not well-formed (duplicate step, empty or too long
/// title, an end before its start).
final class PlanInvalidException extends BeaconPlanException {
  const PlanInvalidException([super.message]);

  static const codeNumber = 1345;
}

/// Poll options contain duplicates after server-side normalization.
final class PollDuplicateVariantException extends BeaconPlanException {
  const PollDuplicateVariantException();

  static const codeNumber = 1346;
}
