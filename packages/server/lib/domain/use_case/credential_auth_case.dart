import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '_use_case_base.dart';

/// Shared resolve-or-create-with-invite path for seedless credentials (Google, email).
@Injectable(order: 2)
final class CredentialAuthCase extends UseCaseBase {
  CredentialAuthCase(
    this._userRepository,
    this._verifiedContactRepository,
    this._invitationCase, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;
  final VerifiedContactRepositoryPort _verifiedContactRepository;
  final InvitationCase _invitationCase;

  /// Returns account id after login or signup.
  Future<String> resolveOrCreate({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? inviteId,
    Map<String, Object?>? publicData,
    List<AssertedContact> assertedContacts = const [],
  }) async {
    final authoritative = AssertedContact.authoritativeOnly(assertedContacts);

    final existing = await _findByCredential(type, identifier);
    if (existing != null) {
      await _userRepository.addVerifiedContacts(
        accountId: existing.id,
        source: type,
        contacts: authoritative,
      );
      await _acceptInviteIfPresent(inviteId: inviteId, userId: existing.id);
      return existing.id;
    }

    final matchedAccountIds = await _verifiedContactRepository
        .findAccountIdsByContacts(
          authoritative.map((c) => (kind: c.kind, value: c.value)),
        );
    if (matchedAccountIds.length > 1) {
      throw const AmbiguousIdentityException();
    }
    if (matchedAccountIds.length == 1) {
      final accountId = matchedAccountIds.single;
      final linkedAccountId = await _userRepository.linkCredentialWithContacts(
        accountId: accountId,
        type: type,
        identifier: identifier,
        publicData: publicData,
        contacts: authoritative,
      );
      await _acceptInviteIfPresent(inviteId: inviteId, userId: linkedAccountId);
      return linkedAccountId;
    }

    return _createAccount(
      type: type,
      identifier: identifier,
      displayName: displayName,
      inviteId: inviteId,
      publicData: publicData,
      contacts: authoritative,
    );
  }

  /// Whether an account already owns the `(type, identifier)` credential.
  Future<bool> credentialExists({
    required CredentialType type,
    required String identifier,
  }) async => await _findByCredential(type, identifier) != null;

  /// Whether [normalizedEmail] is known via `email_otp` or a verified contact.
  Future<bool> emailIsRegistered(String normalizedEmail) async {
    if (await credentialExists(
      type: CredentialType.emailOtp,
      identifier: normalizedEmail,
    )) {
      return true;
    }
    final accountId = await _verifiedContactRepository.getAccountIdByContact(
      kind: ContactKind.email,
      value: normalizedEmail,
    );
    return accountId != null;
  }

  Future<String> _createAccount({
    required CredentialType type,
    required String identifier,
    required String displayName,
    required List<AssertedContact> contacts,
    String? inviteId,
    Map<String, Object?>? publicData,
  }) async {
    if (inviteId == null || inviteId.isEmpty) {
      if (env.isNeedInvite) {
        throw const OidcInviteRequiredException();
      }
      try {
        final user = await _userRepository.createWithCredential(
          type: type,
          identifier: identifier,
          displayName: displayName,
          publicData: publicData,
          contacts: contacts,
        );
        return user.id;
      } on ContactConflictException catch (_) {
        return _retryLinkAfterContactConflict(
          type: type,
          identifier: identifier,
          publicData: publicData,
          contacts: contacts,
          inviteId: inviteId,
        );
      }
    }

    try {
      final user = await _userRepository.createInvitedWithCredential(
        invitationId: inviteId,
        type: type,
        identifier: identifier,
        displayName: displayName,
        publicData: publicData,
        contacts: contacts,
      );
      return user.id;
    } on ContactConflictException catch (_) {
      return _retryLinkAfterContactConflict(
        type: type,
        identifier: identifier,
        publicData: publicData,
        contacts: contacts,
        inviteId: inviteId,
      );
    }
  }

  Future<String> _retryLinkAfterContactConflict({
    required CredentialType type,
    required String identifier,
    required List<AssertedContact> contacts,
    String? inviteId,
    Map<String, Object?>? publicData,
  }) async {
    final matchedAccountIds = await _verifiedContactRepository
        .findAccountIdsByContacts(
          contacts.map((c) => (kind: c.kind, value: c.value)),
        );
    if (matchedAccountIds.length != 1) {
      throw const AmbiguousIdentityException();
    }
    final accountId = matchedAccountIds.single;
    final linkedAccountId = await _userRepository.linkCredentialWithContacts(
      accountId: accountId,
      type: type,
      identifier: identifier,
      publicData: publicData,
      contacts: contacts,
    );
    await _acceptInviteIfPresent(inviteId: inviteId, userId: linkedAccountId);
    return linkedAccountId;
  }

  Future<void> _acceptInviteIfPresent({
    required String? inviteId,
    required String userId,
  }) async {
    if (inviteId == null || inviteId.isEmpty) return;
    try {
      await _invitationCase.acceptAsExisting(code: inviteId, userId: userId);
    } on IdNotFoundException catch (e, st) {
      logger.info(
        'invite befriend skipped for $userId on $inviteId: ${e.description}',
        e,
        st,
      );
    } on InvitationWrongException catch (e, st) {
      logger.info(
        'invite befriend skipped for $userId on $inviteId: ${e.description}',
        e,
        st,
      );
    }
  }

  Future<UserEntity?> _findByCredential(
    CredentialType type,
    String identifier,
  ) async {
    try {
      return await _userRepository.getByCredential(
        type: type.wire,
        identifier: identifier,
      );
    } catch (_) {
      return null;
    }
  }
}
