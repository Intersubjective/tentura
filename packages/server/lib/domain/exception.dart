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

final class EvaluationException extends ExceptionBase {
  EvaluationException({
    required EvaluationExceptionCode evaluationCode,
    String? description,
  }) : super(
         code: EvaluationExceptionCodes(evaluationCode),
         description: description ?? evaluationCode.name,
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
