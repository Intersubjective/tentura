import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';

/// Read-only token lookup status for email magic-link confirmation.
enum EmailAuthTokenStatus { valid, expired, consumed, missing }

/// Result of peeking a magic-link token without consuming it.
class EmailAuthPeek {
  const EmailAuthPeek({
    required this.status,
    this.inviteCode,
    this.isLink = false,
  });

  final EmailAuthTokenStatus status;

  /// Present when the transaction was created from an invite landing page.
  final String? inviteCode;

  /// Settings link mode (attach email to an existing account, no session).
  final bool isLink;

  factory EmailAuthPeek.fromTransaction({
    required EmailAuthTokenStatus status,
    EmailAuthTransactionEntity? tx,
  }) {
    if (tx == null) {
      return EmailAuthPeek(status: status);
    }
    final linkId = tx.linkAccountId;
    return EmailAuthPeek(
      status: status,
      inviteCode: tx.inviteCode,
      isLink: linkId != null && linkId.isNotEmpty,
    );
  }
}

/// Outcome of `EmailAuthCase.start` (ADR 0009 `email_start_outcome` tags).
enum EmailAuthStartOutcome {
  invalidFormat('invalid_format'),
  rateLimited('rate_limited'),
  mailUnconfigured('mail_unconfigured'),
  inviteRequiredSkip('invite_required_skip'),
  sent('sent'),
  unexpectedError('unexpected_error');

  const EmailAuthStartOutcome(this.tag);
  final String tag;
}

/// Result of starting email magic-link auth (domain, HTTP-free).
final class EmailAuthStartResult {
  const EmailAuthStartResult({
    required this.correlationId,
    required this.outcome,
  });

  final String correlationId;
  final EmailAuthStartOutcome outcome;
}

/// Successful email magic-link confirmation (domain outcome, HTTP-free).
sealed class EmailAuthConfirmOutcome {
  const EmailAuthConfirmOutcome();
}

/// Login/signup: session minted; controller sets cookie and redirects.
final class EmailAuthLoginConfirmed extends EmailAuthConfirmOutcome {
  const EmailAuthLoginConfirmed({
    required this.sessionToken,
    required this.isNewAccount,
    this.inviteCode,
  });

  final String sessionToken;
  final String? inviteCode;

  /// True only when a brand-new account was created (drives `new=1` redirect).
  final bool isNewAccount;
}

/// Settings link mode: email attached; no session minted.
final class EmailAuthLinkConfirmed extends EmailAuthConfirmOutcome {
  const EmailAuthLinkConfirmed();
}

/// Token state errors for magic-link peek/confirm.
sealed class EmailAuthTokenException implements Exception {
  const EmailAuthTokenException();
}

final class EmailAuthTokenExpiredException extends EmailAuthTokenException {
  const EmailAuthTokenExpiredException();
}

final class EmailAuthTokenAlreadyUsedException extends EmailAuthTokenException {
  const EmailAuthTokenAlreadyUsedException();
}

final class EmailAuthTokenMissingException extends EmailAuthTokenException {
  const EmailAuthTokenMissingException();
}
