import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class EmailAuthCase extends UseCaseBase {
  EmailAuthCase(
    this._transactionRepository,
    this._emailSender,
    this._credentialAuthCase,
    this._userRepository,
    this._sessionCase, {
    required super.env,
    required super.logger,
  });

  final EmailAuthTransactionRepositoryPort _transactionRepository;
  final EmailSenderPort _emailSender;
  final CredentialAuthCase _credentialAuthCase;
  final UserRepositoryPort _userRepository;
  final SessionCase _sessionCase;

  static String hashFingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// Sends a magic link when rate limits allow. Always completes without throwing
  /// for accepted email format (enumeration-safe at the controller).
  Future<EmailAuthStartResult> start({
    required String email,
    required String ipFingerprint,
    required String userAgentFingerprint,
    String? inviteCode,
    String? linkAccountId,
    String? attemptId,
  }) async {
    final correlationId =
        attemptId ?? EmailAuthTransactionEntity.newId;
    final isLink = linkAccountId != null && linkAccountId.isNotEmpty;
    final normalized = normalizeAuthEmail(email);
    if (!isValidAuthEmailFormat(normalized)) {
      return EmailAuthStartResult(
        correlationId: correlationId,
        outcome: EmailAuthStartOutcome.invalidFormat,
      );
    }
    if (!await _withinRateLimits(
      normalizedEmail: normalized,
      inviteCode: inviteCode,
      ipHash: hashFingerprint(ipFingerprint),
    )) {
      logger.info('email auth start rate-limited');
      return EmailAuthStartResult(
        correlationId: correlationId,
        outcome: EmailAuthStartOutcome.rateLimited,
      );
    }
    if (!env.isEmailAuthConfigured) {
      logger.warning('email auth start skipped: Resend not configured');
      return EmailAuthStartResult(
        correlationId: correlationId,
        outcome: EmailAuthStartOutcome.mailUnconfigured,
      );
    }

    if (!isLink &&
        (inviteCode == null || inviteCode.isEmpty) &&
        env.isNeedInvite) {
      final registered = await _credentialAuthCase.emailIsRegistered(normalized);
      if (!registered) {
        logger.info('email auth start skipped: unregistered email, invite required');
        return EmailAuthStartResult(
          correlationId: correlationId,
          outcome: EmailAuthStartOutcome.inviteRequiredSkip,
        );
      }
    }

    try {
      final token = await _transactionRepository.create(
        normalizedEmail: normalized,
        inviteCode: inviteCode,
        linkAccountId: linkAccountId,
        expiresIn: env.emailAuthTtl,
        userAgentHash: hashFingerprint(userAgentFingerprint),
        ipHash: hashFingerprint(ipFingerprint),
        transactionId: correlationId,
      );
      final verifyUrl = Uri.parse(env.publicOrigin).replace(
        path: '/auth/email/verify',
        queryParameters: {'t': token},
      );
      await _emailSender.sendMagicLink(
        to: normalized,
        verifyUrl: verifyUrl.toString(),
      );
      return EmailAuthStartResult(
        correlationId: correlationId,
        outcome: EmailAuthStartOutcome.sent,
      );
    } catch (e, st) {
      logger.severe('email auth start sender failed', e, st);
      return EmailAuthStartResult(
        correlationId: correlationId,
        outcome: EmailAuthStartOutcome.unexpectedError,
      );
    }
  }

  /// Read-only token status for the confirmation page (never consumes).
  Future<EmailAuthPeek> peek(String plaintextToken) async {
    final row = await _transactionRepository.peekByToken(plaintextToken);
    return EmailAuthPeek.fromTransaction(status: row.status, tx: row.tx);
  }

  /// Confirms sign-in or email link after user action. Consumes the token LAST.
  Future<EmailAuthConfirmOutcome> confirm(String plaintextToken) async {
    final peekRow = await _transactionRepository.peekByToken(plaintextToken);
    _throwForStatus(peekRow.status);
    final tx = peekRow.tx!;

    final emailContact = AssertedContact.email(
      rawEmail: tx.normalizedEmail,
      authoritative: true,
    )!;

    final linkAccountId = tx.linkAccountId;
    if (linkAccountId != null && linkAccountId.isNotEmpty) {
      await _userRepository.linkCredentialToAccountStrict(
        accountId: linkAccountId,
        type: CredentialType.emailOtp,
        identifier: tx.normalizedEmail,
        contacts: [emailContact],
      );
      await _consumeLast(plaintextToken);
      return const EmailAuthLinkConfirmed();
    }

    final resolved = await _mintLoginSession(
      normalizedEmail: tx.normalizedEmail,
      inviteCode: tx.inviteCode,
    );
    await _consumeLast(plaintextToken);
    return EmailAuthLoginConfirmed(
      sessionToken: resolved.sessionToken,
      inviteCode: tx.inviteCode,
      isNewAccount: resolved.isNewAccount,
    );
  }

  /// QA-only immediate sign-in (controller must gate env + domain).
  Future<({String sessionToken, bool isNewAccount})> qaTestLogin({
    required String normalizedEmail,
    String? inviteCode,
  }) => _mintLoginSession(
    normalizedEmail: normalizedEmail,
    inviteCode: inviteCode,
    bypassInviteForNewAccount: true,
  );

  Future<({String sessionToken, bool isNewAccount})> _mintLoginSession({
    required String normalizedEmail,
    String? inviteCode,
    bool bypassInviteForNewAccount = false,
  }) async {
    final emailContact = AssertedContact.email(
      rawEmail: normalizedEmail,
      authoritative: true,
    )!;

    final resolved = await _credentialAuthCase.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: normalizedEmail,
      displayName: displayNameFromEmail(normalizedEmail),
      inviteId: inviteCode,
      assertedContacts: [emailContact],
      bypassInviteForNewAccount: bypassInviteForNewAccount,
    );
    final credentialId = await _userRepository.findCredentialId(
      type: CredentialType.emailOtp,
      identifier: normalizedEmail,
    );
    final sessionToken = await _sessionCase.createSession(
      accountId: resolved.accountId,
      credentialId: credentialId,
    );
    return (sessionToken: sessionToken, isNewAccount: resolved.isNewAccount);
  }

  Future<void> _consumeLast(String plaintextToken) async {
    final consumed = await _transactionRepository.consumeByToken(plaintextToken);
    if (consumed == null) {
      logger.warning(
        'email auth confirm: token consume failed after successful auth '
        '(concurrent use or race)',
      );
    }
  }

  void _throwForStatus(EmailAuthTokenStatus status) {
    switch (status) {
      case EmailAuthTokenStatus.valid:
        return;
      case EmailAuthTokenStatus.expired:
        throw const EmailAuthTokenExpiredException();
      case EmailAuthTokenStatus.consumed:
        throw const EmailAuthTokenAlreadyUsedException();
      case EmailAuthTokenStatus.missing:
        throw const EmailAuthTokenMissingException();
    }
  }

  Future<bool> _withinRateLimits({
    required String normalizedEmail,
    required String ipHash,
    String? inviteCode,
  }) async {
    final window = env.emailAuthRateLimitWindow;
    if (await _transactionRepository.countRecentByEmail(
          normalizedEmail: normalizedEmail,
          window: window,
        ) >=
        env.emailAuthMaxPerEmail) {
      return false;
    }
    if (await _transactionRepository.countRecentByIpHash(
          ipHash: ipHash,
          window: window,
        ) >=
        env.emailAuthMaxPerIp) {
      return false;
    }
    if (inviteCode != null &&
        inviteCode.isNotEmpty &&
        await _transactionRepository.countRecentByInviteCode(
              inviteCode: inviteCode,
              window: window,
            ) >=
            env.emailAuthMaxPerInvite) {
      return false;
    }
    return true;
  }
}
