import 'dart:convert';

import 'exception_codes.dart';

part 'exception/fcm_exceptions.dart';

base class ExceptionBase implements Exception {
  const ExceptionBase({
    required this.code,
    required this.description,
    this.path = '',
  });

  final ExceptionCodes code;
  final String description;
  final String path;

  Map<String, Object> get toMap => {
    'message': description,
    'extensions': {'code': '${code.codeNumber}', 'path': path},
  };

  @override
  String toString() => jsonEncode(toMap);
}

final class UnspecifiedException extends ExceptionBase {
  const UnspecifiedException({
    String? description,
    String? path,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.unspecifiedException,
         ),
         description: description ?? 'Unspecified exception',
         path: path ?? '',
       );
}

final class IdNotFoundException extends ExceptionBase {
  const IdNotFoundException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idNotFoundException,
         ),
         description: description ?? 'Id not found: [$id]',
       );
}

final class IdWrongException extends ExceptionBase {
  const IdWrongException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idWrongException,
         ),
         description: description ?? 'Wrong Id: [$id]',
       );
}

final class IdDuplicateException extends ExceptionBase {
  const IdDuplicateException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idDuplicateException,
         ),
         description: description ?? 'Id already exists: [$id]',
       );
}

/// Upload (image or attachment) exceeds the server-side byte cap. Maps to 413.
final class PayloadTooLargeException extends ExceptionBase {
  const PayloadTooLargeException({String? description})
    : super(
        code: const GeneralExceptionCodes(
          GeneralExceptionCode.payloadTooLargeException,
        ),
        description: description ?? 'Upload exceeds maximum allowed size',
      );
}

/// Too many create/write operations from one actor in the configured window
/// (spam / abuse control). Maps to 429.
final class RateLimitedException extends ExceptionBase {
  const RateLimitedException({String? description})
    : super(
        code: const GeneralExceptionCodes(
          GeneralExceptionCode.rateLimitedException,
        ),
        description:
            description ?? 'Too many requests, please slow down and retry later',
      );
}

final class PemKeyWrongException extends ExceptionBase {
  const PemKeyWrongException({
    String key = '',
    String? description,
  }) : super(
         code: const AuthExceptionCodes(
           AuthExceptionCode.authPemKeyWrongException,
         ),
         description: description ?? 'Wrong PEM keys: [$key]',
       );

  @override
  String toString() => 'Wrong PEM keys: [$description]';
}

final class AuthorizationHeaderWrongException extends ExceptionBase {
  const AuthorizationHeaderWrongException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAuthorizationHeaderWrongException,
        ),
        description: description ?? 'Wrong Authorization header',
      );
}

final class UnauthorizedException extends ExceptionBase {
  const UnauthorizedException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authUnauthorizedException,
        ),
        description: description ?? 'User is not authorized',
      );
}

final class InvitationWrongException extends ExceptionBase {
  const InvitationWrongException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authInvitationWrongException,
        ),
        description: description ?? 'Wrong invitation code',
      );
}

/// Linking a credential whose `(type, identifier)` already exists (on this or
/// another account). Conflict policy: never auto-merge — refuse. Maps to 409.
final class CredentialConflictException extends ExceptionBase {
  const CredentialConflictException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authCredentialConflictException,
        ),
        description: description ?? 'Credential already linked',
      );
}

/// Removing the account's only remaining credential. Removal policy: an account
/// must keep at least one credential. Maps to 409.
final class LastCredentialException extends ExceptionBase {
  const LastCredentialException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authLastCredentialException,
        ),
        description: description ?? 'Cannot remove the last credential',
      );
}

final class OidcStateMismatchException extends ExceptionBase {
  const OidcStateMismatchException({String? description})
    : super(
        code: const AuthExceptionCodes(AuthExceptionCode.oidcStateMismatch),
        description: description ?? 'OAuth state mismatch',
      );
}

final class OidcTokenExchangeFailedException extends ExceptionBase {
  const OidcTokenExchangeFailedException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.oidcTokenExchangeFailed,
        ),
        description: description ?? 'OAuth token exchange failed',
      );
}

final class OidcIdTokenInvalidException extends ExceptionBase {
  const OidcIdTokenInvalidException({String? description})
    : super(
        code: const AuthExceptionCodes(AuthExceptionCode.oidcIdTokenInvalid),
        description: description ?? 'OIDC id_token invalid',
      );
}

final class OidcProviderDisabledException extends ExceptionBase {
  const OidcProviderDisabledException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.oidcProviderDisabled,
        ),
        description: description ?? 'OIDC provider is not configured',
      );
}

final class OidcInviteRequiredException extends ExceptionBase {
  const OidcInviteRequiredException({String? description})
    : super(
        code: const AuthExceptionCodes(AuthExceptionCode.oidcInviteRequired),
        description: description ?? 'Invite required for new accounts',
      );
}

/// Multiple distinct accounts matched the same authoritative contact(s).
final class AmbiguousIdentityException extends ExceptionBase {
  const AmbiguousIdentityException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAmbiguousIdentity,
        ),
        description: description ?? 'Ambiguous identity match',
      );
}

/// A verified contact is already owned by another account during create/link.
final class ContactConflictException extends ExceptionBase {
  const ContactConflictException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authCredentialConflictException,
        ),
        description: description ?? 'Verified contact conflict',
      );
}

final class BeaconCreateException extends ExceptionBase {
  const BeaconCreateException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconCreateException,
        ),
        description: description ?? 'Beacon create error',
      );
}

final class BeaconNeedSummaryTooShortException extends ExceptionBase {
  const BeaconNeedSummaryTooShortException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconNeedSummaryTooShort,
        ),
        description:
            description ?? 'Need summary must be at least 16 characters',
      );
}

/// Source message already has a non-removed fact card (race-safe guard).
final class BeaconFactCardAlreadyPinnedException extends ExceptionBase {
  const BeaconFactCardAlreadyPinnedException({
    required this.existingFactCardId,
    String? description,
  }) : super(
          code: const BeaconExceptionCodes(
            BeaconExceptionCode.beaconFactCardAlreadyPinned,
          ),
          description: description ?? 'Fact already pinned for this message',
        );

  final String existingFactCardId;

  @override
  Map<String, Object> get toMap => {
        'message': description,
        'extensions': {
          'code': '${code.codeNumber}',
          'path': path,
          'factCardId': existingFactCardId,
        },
      };
}

/// `primaryNeedSlug` is not one of the 37 allowed capability slugs.
final class BeaconPrimaryNeedInvalidException extends ExceptionBase {
  const BeaconPrimaryNeedInvalidException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconPrimaryNeedInvalid,
        ),
        description: description ?? 'Unknown capability slug',
      );
}

/// A non-null `primaryNeedSlug` is absent from the submitted `needs`, or the
/// primary is null while `needs` is non-empty.
final class BeaconPrimaryNeedNotInNeedsException extends ExceptionBase {
  const BeaconPrimaryNeedNotInNeedsException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconPrimaryNeedNotInNeeds,
        ),
        description:
            description ?? 'Primary capability must be one of the needs',
      );
}

/// A media id in `beaconSetMedia` is outside the attached-or-staged set.
final class BeaconImageNotAttachedException extends ExceptionBase {
  const BeaconImageNotAttachedException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconImageNotAttached,
        ),
        description: description ?? 'Image is not attached to this request',
      );
}

/// The requested cover id is outside the desired media set.
final class BeaconCoverNotAttachedException extends ExceptionBase {
  const BeaconCoverNotAttachedException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconCoverNotAttached,
        ),
        description: description ?? 'Cover image is not part of this update',
      );
}

/// Duplicate media ids, an over-cap list, an unknown `coverSource`, or a
/// null/non-null cover mismatch with the desired image list.
final class BeaconMediaInvalidException extends ExceptionBase {
  const BeaconMediaInvalidException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconMediaInvalid,
        ),
        description: description ?? 'Invalid media update',
      );
}

final class BeaconChildCreateForbiddenException extends ExceptionBase {
  const BeaconChildCreateForbiddenException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconChildCreateForbidden,
        ),
        description: description ?? 'Child request creation is not allowed',
      );
}

final class BeaconStructuralOnlyException extends ExceptionBase {
  const BeaconStructuralOnlyException({required String beaconId})
    : super(
        code: const GeneralExceptionCodes(
          GeneralExceptionCode.idNotFoundException,
        ),
        description: 'Structural request record only: [$beaconId]',
      );
}

final class BeaconParentNotCoordinatableException extends ExceptionBase {
  const BeaconParentNotCoordinatableException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconParentNotCoordinatable,
        ),
        description:
            description ?? 'Parent request cannot accept child requests',
      );
}

final class BeaconPromotionSourceInvalidException extends ExceptionBase {
  const BeaconPromotionSourceInvalidException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconPromotionSourceInvalid,
        ),
        description: description ?? 'Promotion source message is not eligible',
      );
}

final class BeaconSourceAlreadyPromotedException extends ExceptionBase {
  const BeaconSourceAlreadyPromotedException({
    this.existingChildBeaconId,
    String? description,
  }) : super(
         code: const BeaconExceptionCodes(
           BeaconExceptionCode.beaconSourceAlreadyPromoted,
         ),
         description:
             description ?? 'Source message already has a published child',
       );

  final String? existingChildBeaconId;

  @override
  Map<String, Object> get toMap => {
    'message': description,
    'extensions': {
      'code': '${code.codeNumber}',
      'path': path,
      if (existingChildBeaconId != null)
        'beaconId': existingChildBeaconId!,
    },
  };
}

final class BeaconChildCommandConflictException extends ExceptionBase {
  const BeaconChildCommandConflictException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconChildCommandConflict,
        ),
        description:
            description ??
            'Client command id was reused with different input',
      );
}

final class BeaconChildCommandGoneException extends ExceptionBase {
  const BeaconChildCommandGoneException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconChildCommandGone,
        ),
        description:
            description ?? 'Prior child draft for this command was deleted',
      );
}

final class DiscussionScopeDisabledException extends ExceptionBase {
  const DiscussionScopeDisabledException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.discussionScopeDisabled,
        ),
        description:
            description ?? 'Only the General discussion is available',
      );
}

final class CoordinationKindDisabledException extends ExceptionBase {
  const CoordinationKindDisabledException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.coordinationKindDisabled,
        ),
        description:
            description ?? 'This coordination item type is not supported',
      );
}

final class BeaconHierarchyCursorInvalidException extends ExceptionBase {
  const BeaconHierarchyCursorInvalidException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconHierarchyCursorInvalid,
        ),
        description:
            description ?? 'BEACON_HIERARCHY_CURSOR_INVALID',
      );
}

/// Fact edit/restore base seq is stale; [currentSeq] is the head revision.
final class BeaconFactCardEditConflictException extends ExceptionBase {
  const BeaconFactCardEditConflictException({
    required this.currentSeq,
    String? description,
  }) : super(
         code: const BeaconExceptionCodes(
           BeaconExceptionCode.beaconFactCardEditConflict,
         ),
         description: description ?? 'Fact card was edited concurrently',
       );

  final int currentSeq;

  Map<String, Object> get extensions => {
    'code': '${code.codeNumber}',
    'path': path,
    'currentSeq': currentSeq,
  };

  @override
  Map<String, Object> get toMap => {
    'message': description,
    'extensions': extensions,
  };
}

final class BeaconFactCardRemovedException extends ExceptionBase {
  const BeaconFactCardRemovedException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconFactCardRemoved,
        ),
        description: description ?? 'Fact card was removed',
      );
}

final class BeaconFactCardRateLimitedException extends ExceptionBase {
  const BeaconFactCardRateLimitedException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconFactCardRateLimited,
        ),
        description: description ?? 'Too many fact card edits',
      );
}

/// The operation is only defined for a Request; the beacon is a Post.
final class BeaconNotRequestException extends ExceptionBase {
  const BeaconNotRequestException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconNotRequest,
        ),
        description: description ?? 'Operation is only available for Requests',
      );
}

// «Who'll take it?» (baton) — plan §2.2/B2
// (`docs/plans/baton-who-takes-it-plan.md`).

final class BatonNotFoundException extends ExceptionBase {
  const BatonNotFoundException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.batonNotFound),
        description: description ?? 'Baton not found',
      );
}

final class BatonNotAuthorException extends ExceptionBase {
  const BatonNotAuthorException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.batonNotAuthor),
        description: description ?? 'Only the baton author may do this',
      );
}

final class BatonNotCandidateException extends ExceptionBase {
  const BatonNotCandidateException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonNotCandidate,
        ),
        description: description ?? 'Not a candidate on this baton',
      );
}

final class BatonNotCollectingException extends ExceptionBase {
  const BatonNotCollectingException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonNotCollecting,
        ),
        description: description ?? 'Baton is no longer collecting answers',
      );
}

final class BatonInvalidCandidatesException extends ExceptionBase {
  const BatonInvalidCandidatesException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonInvalidCandidates,
        ),
        description: description ?? 'Invalid candidate list',
      );
}

final class BatonAlreadyActiveException extends ExceptionBase {
  const BatonAlreadyActiveException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonAlreadyActive,
        ),
        description: description ?? 'This message already has a live baton',
      );
}

final class BatonTakerNotAvailableException extends ExceptionBase {
  const BatonTakerNotAvailableException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonTakerNotAvailable,
        ),
        description: description ?? 'No eligible person is available to take it',
      );
}

final class BatonMessageNotEligibleException extends ExceptionBase {
  const BatonMessageNotEligibleException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.batonMessageNotEligible,
        ),
        description: description ?? 'A baton cannot start on this message',
      );
}

final class EvaluationException extends ExceptionBase {
  EvaluationException({
    required EvaluationExceptionCode code,
    String? description,
  }) : super(
         code: EvaluationExceptionCodes(code),
         description: description ?? code.name,
       );
}

final class HelpOfferCoordinationException extends ExceptionBase {
  HelpOfferCoordinationException({
    required HelpOfferCoordinationExceptionCode coordinationCode,
    String? description,
  }) : super(
         code: HelpOfferCoordinationExceptionCodes(coordinationCode),
         description: description ?? coordinationCode.name,
       );
}

final class ConstellationException extends ExceptionBase {
  ConstellationException({
    required ConstellationExceptionCode constellationCode,
    String? description,
  }) : super(
         code: ConstellationExceptionCodes(constellationCode),
         description: description ?? _constellationDescription(constellationCode),
       );
}

String _constellationDescription(ConstellationExceptionCode code) =>
    switch (code) {
      ConstellationExceptionCode.invalidTarget =>
        'Invalid constellation anchor target',
      ConstellationExceptionCode.invalidCoordinates =>
        'Invalid constellation anchor coordinates',
      ConstellationExceptionCode.unsupportedCoordinateSpace =>
        'Unsupported coordinate space',
      ConstellationExceptionCode.targetUnavailable =>
        'Constellation anchor target unavailable',
    };

/// Plan («либретто», #220): save/restore base is stale and both sides changed
/// the same steps ([conflictStepIds]), or a restore lost the CAS race.
final class PlanEditConflictException extends ExceptionBase {
  const PlanEditConflictException({
    required this.currentSeq,
    this.conflictStepIds = const [],
    String? description,
  }) : super(
         code: const BeaconExceptionCodes(BeaconExceptionCode.planEditConflict),
         description: description ?? 'Plan was edited concurrently',
       );

  final int currentSeq;

  final List<String> conflictStepIds;

  Map<String, Object> get extensions => {
    'code': '${code.codeNumber}',
    'path': path,
    'currentSeq': currentSeq,
    'conflictStepIds': conflictStepIds,
  };

  @override
  Map<String, Object> get toMap => {
    'message': description,
    'extensions': extensions,
  };
}

final class PlanStepNotFoundException extends ExceptionBase {
  const PlanStepNotFoundException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planStepNotFound),
        description: description ?? 'Plan step not found',
      );
}

/// The Request is not in a state that allows plan writes (closed, cancelled,
/// deleted, a Post, or a draft that is not the author's fork copy).
final class PlanNotEditableException extends ExceptionBase {
  const PlanNotEditableException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planNotEditable),
        description: description ?? 'The plan of this request is read-only',
      );
}

/// A one-tap action (push button, «Понятно», «Не успеваю») refers to a state
/// that has moved on: the step was reassigned, removed or already changed.
final class PlanActionStaleException extends ExceptionBase {
  const PlanActionStaleException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planActionStale),
        description: description ?? 'The plan has changed since',
      );
}

final class PlanRestoreSourceMissingException extends ExceptionBase {
  const PlanRestoreSourceMissingException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.planRestoreSourceMissing,
        ),
        description: description ?? 'Plan revision not found',
      );
}

final class PlanRateLimitedException extends ExceptionBase {
  const PlanRateLimitedException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planRateLimited),
        description: description ?? 'Too many plan edits, try again shortly',
      );
}

final class PlanAssigneeNotAdmittedException extends ExceptionBase {
  const PlanAssigneeNotAdmittedException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.planAssigneeNotAdmitted,
        ),
        description:
            description ?? 'Steps can only be assigned to admitted people',
      );
}

/// The plan exceeds a size limit: steps, description or comment length.
final class PlanTooLargeException extends ExceptionBase {
  const PlanTooLargeException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planTooLarge),
        description: description ?? 'The plan exceeds its limits',
      );
}

final class PlanDisabledException extends ExceptionBase {
  const PlanDisabledException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planDisabled),
        description: description ?? 'Request plans are not enabled',
      );
}

/// A plan draft that is not well-formed: unparsable, a duplicate step id, an
/// empty or too long title, an end before its start (size limits are
/// [PlanTooLargeException]).
final class PlanInvalidException extends ExceptionBase {
  const PlanInvalidException({String? description})
    : super(
        code: const BeaconExceptionCodes(BeaconExceptionCode.planInvalid),
        description: description ?? 'The plan is not valid',
      );
}
