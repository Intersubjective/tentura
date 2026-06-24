import 'dart:convert';
import 'dart:math';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';
import '../mapper/user_mapper.dart';

export 'package:tentura_server/domain/entity/user_entity.dart';

@Singleton(
  as: UserRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class UserRepository implements UserRepositoryPort {
  UserRepository(
    this._env,
    this._database,
    this._trustEdgeRepository,
  );

  final Env _env;

  final TenturaDb _database;
  final UserTrustEdgeRepositoryPort _trustEdgeRepository;

  //
  //
  @override
  Future<UserEntity> create({
    required String publicKey,
    required String displayName,
    String? handle,
  }) => _database.transaction<UserEntity>(() async {
    final user = await _database.managers.users.createReturning(
      (o) => o(
        displayName: displayName,
        publicKey: publicKey,
        handle: handle == null || handle.trim().isEmpty
            ? const Value.absent()
            : Value(handle.trim().toLowerCase()),
      ),
    );
    await _createDeviceCredential(accountId: user.id, publicKey: publicKey);
    return userModelToEntity(user);
  });

  /// Dual-write the `ed25519_device` credential alongside the account row so
  /// `getByCredential` resolves it. `user.public_key` is kept in lockstep.
  Future<void> _createDeviceCredential({
    required String accountId,
    required String publicKey,
  }) => _database.managers.accountCredentials.create(
    (o) => o(
      accountId: accountId,
      type: CredentialType.ed25519Device.wire,
      identifier: publicKey,
    ),
  );

  /// Subjective profiles: on invite consumption the inviter gets the invitee
  /// under the invite's addressee name. The invite name always wins over a
  /// pre-existing contact entry. Skips legacy invites without a name. Must be
  /// called inside the consuming transaction.
  Future<void> _upsertInviteContact({
    required String viewerId,
    required String subjectId,
    required String? addresseeName,
  }) async {
    final name = addresseeName?.trim();
    if (name == null || name.isEmpty || viewerId == subjectId) return;
    await _database
        .into(_database.userContacts)
        .insert(
          UserContactsCompanion.insert(
            viewerId: viewerId,
            subjectId: subjectId,
            contactName: name,
          ),
          onConflict: DoUpdate(
            (_) => UserContactsCompanion(
              contactName: Value(name),
              updatedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          ),
        );
  }

  // TBD: move to SQL
  //
  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String displayName,
    String? handle,
  }) => _database.transaction<UserEntity>(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingle();
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
      );
    }
    if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(description: 'Invitation expired!');
    }

    final user = await _database.managers.users.createReturning(
      (o) => o(
        displayName: displayName,
        publicKey: publicKey,
        handle: handle == null || handle.trim().isEmpty
            ? const Value.absent()
            : Value(handle.trim().toLowerCase()),
      ),
    );
    await _createDeviceCredential(accountId: user.id, publicKey: publicKey);
    final changedRowCount = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .update((o) => o(invitedId: Value(user.id)));
    if (changedRowCount == 0) {
      throw const InvitationWrongException(
        description: 'Can`t update invitation!',
      );
    }

    await _database.managers.voteUsers.bulkCreate(
      (o) => [
        o(subject: user.id, object: invitation.userId, amount: 1),
        o(subject: invitation.userId, object: user.id, amount: 1),
      ],
    );
    await _applyReciprocalTrustEdges(
      userA: user.id,
      userB: invitation.userId,
    );

    await _upsertInviteContact(
      viewerId: invitation.userId,
      subjectId: user.id,
      addresseeName: invitation.addresseeName,
    );

    if (invitation.beaconId != null) {
      await _database.into(_database.inboxItems).insert(
        InboxItemsCompanion.insert(
          userId: user.id,
          beaconId: invitation.beaconId!,
          status: const Value(0),
          forwardCount: const Value(1),
          latestForwardAt: Value(PgDateTime(DateTime.timestamp())),
          latestNotePreview: const Value(''),
          rejectionMessage: const Value(''),
        ),
        onConflict: DoNothing(),
      );
    }

    return userModelToEntity(user);
  });

  /// Unique 44-char placeholder satisfying Hasura `String!` on `user.public_key`.
  Future<String> _generatePlaceholderPublicKey() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      var key = base64UrlEncode(bytes).replaceAll('=', '');
      if (key.length < 44) {
        key = key.padRight(44, 'A');
      } else if (key.length > 44) {
        key = key.substring(0, 44);
      }
      final exists = await _database.managers.users
          .filter((e) => e.publicKey(key))
          .getSingleOrNull();
      if (exists == null) return key;
    }
    throw const IdDuplicateException(description: 'Could not allocate public_key');
  }

  Future<UserEntity> _createUserWithCredential({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) async {
    final publicKey = await _generatePlaceholderPublicKey();
    final user = await _database.managers.users.createReturning(
      (o) => o(
        displayName: displayName,
        publicKey: publicKey,
        handle: handle == null || handle.trim().isEmpty
            ? const Value.absent()
            : Value(handle.trim().toLowerCase()),
      ),
    );
    await _database.managers.accountCredentials.create(
      (o) => o(
        accountId: user.id,
        type: type.wire,
        identifier: identifier,
        publicData: publicData == null
            ? const Value.absent()
            : Value(publicData),
      ),
    );
    await _insertAuthoritativeContacts(
      accountId: user.id,
      source: type,
      contacts: contacts,
    );
    return userModelToEntity(user);
  }

  @override
  Future<UserEntity> createWithCredential({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) => _database.transaction<UserEntity>(
    () => _createUserWithCredential(
      type: type,
      identifier: identifier,
      displayName: displayName,
      handle: handle,
      publicData: publicData,
      contacts: contacts,
    ),
  );

  @override
  Future<UserEntity> createInvitedWithCredential({
    required String invitationId,
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) => _database.transaction<UserEntity>(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingle();
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
      );
    }
    if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(description: 'Invitation expired!');
    }

    final user = await _createUserWithCredential(
      type: type,
      identifier: identifier,
      displayName: displayName,
      handle: handle,
      publicData: publicData,
      contacts: contacts,
    );
    final changedRowCount = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .update((o) => o(invitedId: Value(user.id)));
    if (changedRowCount == 0) {
      throw const InvitationWrongException(
        description: 'Can`t update invitation!',
      );
    }

    await _database.managers.voteUsers.bulkCreate(
      (o) => [
        o(subject: user.id, object: invitation.userId, amount: 1),
        o(subject: invitation.userId, object: user.id, amount: 1),
      ],
    );
    await _applyReciprocalTrustEdges(
      userA: user.id,
      userB: invitation.userId,
    );

    await _upsertInviteContact(
      viewerId: invitation.userId,
      subjectId: user.id,
      addresseeName: invitation.addresseeName,
    );

    if (invitation.beaconId != null) {
      await _database.into(_database.inboxItems).insert(
        InboxItemsCompanion.insert(
          userId: user.id,
          beaconId: invitation.beaconId!,
          status: const Value(0),
          forwardCount: const Value(1),
          latestForwardAt: Value(PgDateTime(DateTime.timestamp())),
          latestNotePreview: const Value(''),
          rejectionMessage: const Value(''),
        ),
        onConflict: DoNothing(),
      );
    }

    return user;
  });

  //
  //
  @override
  Future<UserEntity> getById(String id) => _database.managers.users
      .filter((e) => e.id(id))
      .getSingle()
      .then(userModelToEntity);

  //
  //
  @override
  Future<UserEntity> getByPublicKey(String publicKey) => _database
      .managers
      .users
      .filter((e) => e.publicKey(publicKey))
      .getSingle()
      .then(userModelToEntity);

  //
  //
  @override
  Future<UserEntity> getByCredential({
    required String type,
    required String identifier,
  }) async {
    final credential = await _database.managers.accountCredentials
        .filter((e) => e.type(type) & e.identifier(identifier))
        .getSingle();
    return getById(credential.accountId);
  }

  //
  //
  @override
  Future<List<AccountCredentialEntity>> listCredentials({
    required String accountId,
  }) => _database.managers.accountCredentials
      .filter((e) => e.accountId.id(accountId))
      .get()
      .then((rows) => rows.map(_credentialModelToEntity).toList());

  //
  //
  @override
  Future<AccountCredentialEntity> addCredential({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
  }) async {
    try {
      final row = await _database.managers.accountCredentials.createReturning(
        (o) => o(
          accountId: accountId,
          type: type.wire,
          identifier: identifier,
          publicData: publicData == null
              ? const Value.absent()
              : Value(publicData),
        ),
      );
      return _credentialModelToEntity(row);
    } on UniqueViolationException catch (_) {
      final existing = await _findCredentialRow(type: type, identifier: identifier);
      if (existing != null && existing.accountId != accountId) {
        throw const CredentialConflictException();
      }
      // Same-account duplicate is idempotent: return the existing credential.
      if (existing != null) {
        return _credentialModelToEntity(existing);
      }
      rethrow;
    }
  }

  //
  //
  @override
  Future<String> linkCredentialWithContacts({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) async {
    final existingOwner = await _findCredentialOwner(
      type: type,
      identifier: identifier,
    );
    if (existingOwner != null) {
      if (existingOwner == accountId) {
        await addVerifiedContacts(
          accountId: accountId,
          source: type,
          contacts: contacts,
        );
      }
      return existingOwner;
    }

    try {
      return await _database.transaction<String>(() async {
        await _database.managers.accountCredentials.create(
          (o) => o(
            accountId: accountId,
            type: type.wire,
            identifier: identifier,
            publicData: publicData == null
                ? const Value.absent()
                : Value(publicData),
          ),
        );
        await _insertAuthoritativeContacts(
          accountId: accountId,
          source: type,
          contacts: contacts,
        );
        return accountId;
      });
    } on UniqueViolationException catch (_) {
      final contactOwner = await _findConflictingContactOwner(
        contacts: AssertedContact.authoritativeOnly(contacts),
      );
      if (contactOwner != null && contactOwner != accountId) {
        throw const ContactConflictException();
      }
      final credentialOwner = await _findCredentialOwner(
        type: type,
        identifier: identifier,
      );
      if (credentialOwner != null) {
        return credentialOwner;
      }
      rethrow;
    }
  }

  //
  //
  @override
  Future<AccountCredentialEntity> linkCredentialToAccountStrict({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) async {
    final authoritative = AssertedContact.authoritativeOnly(contacts);

    // Idempotent: the credential is already linked to this exact account.
    final existing = await _findCredentialRow(type: type, identifier: identifier);
    if (existing != null) {
      if (existing.accountId != accountId) {
        throw const CredentialConflictException();
      }
      // Soft-attach contacts (skip any owned by another account, no throw).
      await addVerifiedContacts(
        accountId: accountId,
        source: type,
        contacts: authoritative,
      );
      return _credentialModelToEntity(existing);
    }

    // Refuse before insert when an authoritative contact is owned elsewhere.
    final contactOwner = await _findConflictingContactOwner(
      contacts: authoritative,
    );
    if (contactOwner != null && contactOwner != accountId) {
      throw const ContactConflictException();
    }

    try {
      return await _database.transaction<AccountCredentialEntity>(() async {
        final row = await _database.managers.accountCredentials.createReturning(
          (o) => o(
            accountId: accountId,
            type: type.wire,
            identifier: identifier,
            publicData: publicData == null
                ? const Value.absent()
                : Value(publicData),
          ),
        );
        await _insertAuthoritativeContacts(
          accountId: accountId,
          source: type,
          contacts: authoritative,
        );
        return _credentialModelToEntity(row);
      });
    } on UniqueViolationException catch (_) {
      // Lost a race — re-resolve ownership and map to the right 409.
      final raced = await _findCredentialRow(type: type, identifier: identifier);
      if (raced != null && raced.accountId != accountId) {
        throw const CredentialConflictException();
      }
      final racedContactOwner = await _findConflictingContactOwner(
        contacts: authoritative,
      );
      if (racedContactOwner != null && racedContactOwner != accountId) {
        throw const ContactConflictException();
      }
      if (raced != null) {
        return _credentialModelToEntity(raced);
      }
      rethrow;
    }
  }

  //
  //
  @override
  Future<String?> findCredentialId({
    required CredentialType type,
    required String identifier,
  }) async =>
      (await _findCredentialRow(type: type, identifier: identifier))?.id;

  @override
  Future<void> addVerifiedContacts({
    required String accountId,
    required CredentialType source,
    List<AssertedContact> contacts = const [],
  }) async {
    for (final contact in AssertedContact.authoritativeOnly(contacts)) {
      final owner = await _database.managers.accountVerifiedContacts
          .filter(
            (e) => e.kind(contact.kind.wire) & e.value(contact.value),
          )
          .getSingleOrNull();
      if (owner == null) {
        try {
          await _database.managers.accountVerifiedContacts.create(
            (o) => o(
              accountId: accountId,
              kind: contact.kind.wire,
              value: contact.value,
              lastSource: source.wire,
            ),
          );
        } on UniqueViolationException catch (_) {
          // Concurrent insert won the race — skip without blocking login.
        }
        continue;
      }
      if (owner.accountId == accountId) {
        await _database.managers.accountVerifiedContacts
            .filter((e) => e.id(owner.id))
            .update(
              (o) => o(
                lastSource: Value(source.wire),
                verifiedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      }
    }
  }

  Future<void> _insertAuthoritativeContacts({
    required String accountId,
    required CredentialType source,
    required List<AssertedContact> contacts,
  }) async {
    for (final contact in AssertedContact.authoritativeOnly(contacts)) {
      final existing = await _database.managers.accountVerifiedContacts
          .filter(
            (e) => e.kind(contact.kind.wire) & e.value(contact.value),
          )
          .getSingleOrNull();
      if (existing != null) {
        if (existing.accountId != accountId) {
          throw const ContactConflictException();
        }
        continue;
      }
      try {
        await _database.managers.accountVerifiedContacts.create(
          (o) => o(
            accountId: accountId,
            kind: contact.kind.wire,
            value: contact.value,
            lastSource: source.wire,
          ),
        );
      } on UniqueViolationException catch (_) {
        final owner = await _database.managers.accountVerifiedContacts
            .filter(
              (e) => e.kind(contact.kind.wire) & e.value(contact.value),
            )
            .getSingleOrNull();
        if (owner?.accountId != accountId) {
          throw const ContactConflictException();
        }
      }
    }
  }

  Future<String?> _findCredentialOwner({
    required CredentialType type,
    required String identifier,
  }) async => (await _findCredentialRow(type: type, identifier: identifier))
      ?.accountId;

  Future<AccountCredential?> _findCredentialRow({
    required CredentialType type,
    required String identifier,
  }) => _database.managers.accountCredentials
      .filter((e) => e.type(type.wire) & e.identifier(identifier))
      .getSingleOrNull();

  Future<String?> _findConflictingContactOwner({
    required List<AssertedContact> contacts,
  }) async {
    for (final contact in contacts) {
      final row = await _database.managers.accountVerifiedContacts
          .filter(
            (e) => e.kind(contact.kind.wire) & e.value(contact.value),
          )
          .getSingleOrNull();
      if (row != null) {
        return row.accountId;
      }
    }
    return null;
  }

  //
  //
  @override
  Future<void> removeCredential({
    required String accountId,
    required String credentialId,
  }) => _database.transaction(() async {
    // Lock the account's credential rows so concurrent removals serialize —
    // otherwise two deletes of different rows could both pass the
    // last-credential guard and leave the account with none.
    final locked = await _database.customSelect(
      'SELECT id FROM public.account_credential '
      r'WHERE account_id = $1 FOR UPDATE',
      variables: [Variable<String>(accountId)],
    ).get();
    final ids = locked.map((r) => r.read<String>('id')).toSet();

    if (!ids.contains(credentialId)) {
      throw IdNotFoundException(id: credentialId);
    }
    if (ids.length <= 1) {
      throw const LastCredentialException();
    }

    // Revoke this credential's live sessions BEFORE deleting the row: the FK is
    // `ON DELETE SET NULL`, so deleting first would orphan (null) the targets
    // and we could never revoke them. Runs in the same `FOR UPDATE` txn.
    await _database.customStatement(
      'UPDATE public.account_session SET revoked_at = now() '
      r'WHERE credential_id = $1 AND revoked_at IS NULL',
      [credentialId],
    );

    await _database.managers.accountCredentials
        .filter((e) => e.accountId.id(accountId) & e.id(credentialId))
        .delete();
  });

  //
  //
  AccountCredentialEntity _credentialModelToEntity(AccountCredential row) =>
      AccountCredentialEntity(
        id: row.id,
        accountId: row.accountId,
        type: CredentialType.fromWire(row.type),
        identifier: row.identifier,
        publicData: (row.publicData as Map?)?.cast<String, Object?>(),
        createdAt: row.createdAt.dateTime,
      );

  //
  //
  @override
  Future<void> update({
    required String id,
    String? displayName,
    String? description,
    String? imageId,
    bool dropImage = false,
    bool setHandle = false,
    String? handle,
  }) => _database.managers.users
      .filter((e) => e.id(id))
      .update(
        (o) => o(
          displayName: Value.absentIfNull(displayName),
          description: Value.absentIfNull(description),
          imageId: dropImage
              ? const Value(null)
              : imageId == null
              ? const Value.absent()
              : Value(UuidValue.fromString(imageId)),
          handle: !setHandle
              ? const Value.absent()
              : (handle == null || handle.trim().isEmpty)
              ? const Value(null)
              : Value(handle.trim().toLowerCase()),
        ),
      );

  //
  //
  @override
  Future<void> deleteById({required String id}) =>
      _database.managers.users.filter((e) => e.id(id)).delete();

  //
  // TBD: move to SQL
  @override
  Future<bool> bindMutual({
    required String invitationId,
    required String userId,
    bool bindFriendship = true,
  }) => _database.transaction<bool>(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingle();
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
      );
    } else if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(description: 'Invitation expired!');
    }

    await _upsertInviteContact(
      viewerId: invitation.userId,
      subjectId: userId,
      addresseeName: invitation.addresseeName,
    );

    if (invitation.beaconId != null) {
      final existingEdge = await _database.managers.beaconForwardEdges
          .filter(
            (e) =>
                e.beaconId.id(invitation.beaconId!) &
                e.senderId.id(invitation.userId) &
                e.recipientId.id(userId) &
                e.cancelledAt.isNull(),
          )
          .getSingleOrNull();
      if (existingEdge == null) {
        await _database.withMutatingUser(userId, () async {
          await _database.managers.beaconForwardEdges.create(
            (o) => o(
              beaconId: invitation.beaconId!,
              senderId: invitation.userId,
              recipientId: userId,
              note: const Value(''),
              parentEdgeId: Value(invitation.parentForwardEdgeId),
            ),
          );
        });
      }
    }

    final invitationsDeletedCount = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .delete();

    if (bindFriendship) {
      await _database.managers.voteUsers.bulkCreate(
        (o) => [
          o(subject: invitation.userId, object: userId, amount: 1),
          o(subject: userId, object: invitation.userId, amount: 1),
        ],
        mode: InsertMode.insertOrIgnore,
        onConflict: DoNothing(),
      );
      await _applyReciprocalTrustEdges(
        userA: invitation.userId,
        userB: userId,
      );
    }

    return invitationsDeletedCount == 1;
  });

  Future<void> _applyReciprocalTrustEdges({
    required String userA,
    required String userB,
  }) async {
    final at = DateTime.timestamp();
    await _trustEdgeRepository.applyEvidenceInTransaction(
      TrustEvidenceBatch(
        sourceUserId: userA,
        at: at,
        items: [
          TrustEvidence(
            targetUserId: userB,
            bin: TrustBin.good,
            count: kTrustVoteEvidenceCount,
          ),
        ],
      ),
    );
    await _trustEdgeRepository.applyEvidenceInTransaction(
      TrustEvidenceBatch(
        sourceUserId: userB,
        at: at,
        items: [
          TrustEvidence(
            targetUserId: userA,
            bin: TrustBin.good,
            count: kTrustVoteEvidenceCount,
          ),
        ],
      ),
    );
  }
}
