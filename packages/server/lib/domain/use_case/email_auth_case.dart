import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class EmailAuthCase extends UseCaseBase {
  EmailAuthCase(
    this._transactionRepository,
    this._emailSender,
    this._credentialAuthCase, {
    required super.env,
    required super.logger,
  });

  final EmailAuthTransactionRepositoryPort _transactionRepository;
  final EmailSenderPort _emailSender;
  final CredentialAuthCase _credentialAuthCase;

  static String hashFingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// Sends a magic link when rate limits allow. Always completes without throwing
  /// for accepted email format (enumeration-safe at the controller).
  Future<void> start({
    required String email,
    required String ipFingerprint,
    required String userAgentFingerprint,
    String? inviteCode,
  }) async {
    final normalized = normalizeAuthEmail(email);
    if (!isValidAuthEmailFormat(normalized)) {
      return;
    }
    if (!await _withinRateLimits(
      normalizedEmail: normalized,
      inviteCode: inviteCode,
      ipHash: hashFingerprint(ipFingerprint),
    )) {
      logger.info('email auth start rate-limited');
      return;
    }
    if (!env.isEmailAuthConfigured) {
      logger.warning('email auth start skipped: Resend not configured');
      return;
    }

    if ((inviteCode == null || inviteCode.isEmpty) && env.isNeedInvite) {
      final registered = await _credentialAuthCase.emailIsRegistered(normalized);
      if (!registered) {
        logger.info('email auth start skipped: unregistered email, invite required');
        return;
      }
    }

    final token = await _transactionRepository.create(
      normalizedEmail: normalized,
      inviteCode: inviteCode,
      expiresIn: env.emailAuthTtl,
      userAgentHash: hashFingerprint(userAgentFingerprint),
      ipHash: hashFingerprint(ipFingerprint),
    );
    final verifyUrl = Uri.parse(env.publicOrigin).replace(
      path: '/auth/email/verify',
      queryParameters: {'t': token},
    );
    await _emailSender.sendMagicLink(
      to: normalized,
      verifyUrl: verifyUrl.toString(),
    );
  }

  /// Consumes token and resolves account. Throws [OidcInviteRequiredException]
  /// when invite-only and no invite on a new account.
  Future<EmailAuthVerifyResult> verify(String plaintextToken) async {
    final tx = await _transactionRepository.consumeByToken(plaintextToken);
    if (tx == null) {
      throw const EmailAuthTokenInvalidException();
    }
    final accountId = await _credentialAuthCase.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: tx.normalizedEmail,
      displayName: displayNameFromEmail(tx.normalizedEmail),
      inviteId: tx.inviteCode,
      assertedContacts: [
        AssertedContact.email(
          rawEmail: tx.normalizedEmail,
          authoritative: true,
        )!,
      ],
    );
    return EmailAuthVerifyResult(
      accountId: accountId,
      inviteCode: tx.inviteCode,
    );
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

/// Invalid, expired, or reused magic-link token.
final class EmailAuthTokenInvalidException implements Exception {
  const EmailAuthTokenInvalidException();
}
