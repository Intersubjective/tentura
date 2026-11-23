import 'dart:convert';
import 'dart:math';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';

import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/invite/invite_origin.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';
import '../mapper/user_mapper.dart';
import 'beacon_access_repository.dart';
import 'beacon_hierarchy_repository.dart';
import 'closure_repository.dart';
import 'post_lock_repository.dart';

export 'package:tentura_server/domain/entity/user_entity.dart';

enum _InviteAcceptanceMode { friendship, forwardOnly, requestAdmission }

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
    this._inviteGenealogyRepository,
    this._inviteSeedPrompt,
  );

  final Env _env;

  final TenturaDb _database;
  final InviteGenealogyRepositoryPort _inviteGenealogyRepository;
  final InviteSeedPromptPort _inviteSeedPrompt;

  @override
  Future<UserEntity> create({
    required String publicKey,
    required String displayName,
    String? handle,
  }) => _database.withTransaction<UserEntity>(() async {
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

  /// ADR 0008: consuming a beacon-tied invite materializes a forward edge
  /// (sharer→invitee). Inbox for the recipient is maintained by DB trigger
  /// `inbox_item_on_forward_insert`. The caller holds the parent chain locks.
  Future<bool> _materializeBeaconInviteForward({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String? parentForwardEdgeId,
  }) async {
    if (senderId == recipientId) return false;
    final existing = await _database.managers.beaconForwardEdges
        .filter(
          (e) =>
              e.beaconId.id(beaconId) &
              e.senderId.id(senderId) &
              e.recipientId.id(recipientId) &
              e.cancelledAt.isNull(),
        )
        .getSingleOrNull();
    if (existing != null) return false;

    final created = await _database
        .into(_database.beaconForwardEdges)
        .insertReturningOrNull(
          BeaconForwardEdgesCompanion.insert(
            beaconId: beaconId,
            senderId: senderId,
            recipientId: recipientId,
            note: const Value(''),
            parentEdgeId: Value(parentForwardEdgeId),
          ),
          onConflict: DoNothing(),
        );
    return created != null;
  }

  /// Signup genealogy can inherit blocks, whose trigger takes the hierarchy
  /// lock. Take it before the claim, together with the Post lock for a Post.
  Future<({BeaconEntity beacon, bool canForward})?> _lockInvitedSignupScope(
    Invitation invitation,
  ) async {
    final beaconId = invitation.beaconId;
    if (beaconId == null) {
      await BeaconHierarchyRepository(_database).lockMutationScope();
      return null;
    }

    Future<Beacon?> read() => _database.managers.beacons
        .filter((e) => e.id(beaconId))
        .getSingleOrNull();

    var row = await read();
    if (row?.kind == BeaconKind.post.value) {
      await PostLockRepository(_database).lockForPostMutation(beaconId);
    } else {
      await BeaconHierarchyRepository(_database).lockMutationScope();
    }
    row = await read();
    if (row == null) throw IdNotFoundException(id: beaconId);
    final beacon = _inviteBeacon(row);
    final expiresAt = row.expiresAt?.dateTime;
    final now = DateTime.timestamp();
    if (beacon.kind == BeaconKind.request) {
      final canForward = await _canForwardRequestInvite(
        beacon,
        issuerId: invitation.userId,
      );
      return (beacon: beacon, canForward: canForward);
    }
    if (!beacon.allowsForward ||
        BeaconPostLifetime.isExpired(
          kind: row.kind,
          status: beacon.status,
          expiresAt: expiresAt,
          now: now,
        )) {
      throw IdNotFoundException(id: beaconId);
    }
    if (!BeaconForwardPolicy.canForward(
      beacon: beacon,
      senderId: invitation.userId,
    )) {
      throw const UnauthorizedException(
        description: 'Forwarding is off for this post',
      );
    }
    return (beacon: beacon, canForward: true);
  }

  BeaconEntity _inviteBeacon(Beacon row) => BeaconEntity(
    id: row.id,
    title: row.title,
    author: UserEntity(id: row.userId ?? ''),
    createdAt: row.createdAt.dateTime,
    updatedAt: row.updatedAt.dateTime,
    expiresAt: row.expiresAt?.dateTime,
    status: BeaconStatus.fromSmallint(row.status),
    kind: BeaconKind.fromValue(row.kind),
    forwardPolicy: BeaconForwardPolicyValue.fromValue(row.forwardPolicy),
  );

  Future<bool> _canForwardRequestInvite(
    BeaconEntity beacon, {
    required String issuerId,
  }) => BeaconForwardPolicy.canForwardRequestInvite(
    beacon: beacon,
    issuerId: issuerId,
    issuerCanReadContent: () =>
        BeaconAccessRepository(_database).canReadContent(
          beaconId: beacon.id,
          viewerId: issuerId,
        ),
  );

  /// Called inside the accepting transaction. Keep every ancestor locked until
  /// commit so a concurrent leave cannot invalidate admission before insertion.
  Future<bool> _lockActiveInviteParentChain(String parentEdgeId) =>
      hasLiveForwardParentChain(
        parentEdgeId,
        readEdge: (edgeId) async {
          final edge = await _database
              .customSelect(
                'SELECT parent_edge_id, cancelled_at IS NULL AS active '
                r'FROM public.beacon_forward_edge WHERE id = $1 FOR UPDATE',
                variables: [Variable<String>(edgeId)],
              )
              .getSingleOrNull();
          return edge == null
              ? null
              : (
                  parentEdgeId: edge.readNullable<String>('parent_edge_id'),
                  active: edge.read<bool>('active'),
                );
        },
      );

  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String displayName,
    String? handle,
    InvitedPostForwardCreated? onPostForwardCreated,
    InvitedRequestLapsed? onRequestLapsed,
  }) => _database.withJoinedTransaction<UserEntity>(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingleOrNull();
    if (invitation == null) {
      throw const InvitationWrongException(
        description: 'Invitation not found',
      );
    }
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
        reason: InvitationWrongReason.used,
      );
    }
    if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(
        description: 'Invitation expired!',
        reason: InvitationWrongReason.expired,
      );
    }

    final scope = await _lockInvitedSignupScope(invitation);

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
    final changedRowCount =
        await (_database.update(_database.invitations)..where(
              (t) => t.id.equals(invitationId) & t.invitedId.isNull(),
            ))
            .write(
              InvitationsCompanion(
                invitedId: Value(user.id),
                inviteOrigin: Value(InviteOrigin.newAccount.key),
                acceptedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
    if (changedRowCount == 0) {
      throw const InvitationWrongException(
        description: 'Can`t update invitation!',
      );
    }

    await _finishInvitedSignup(
      invitation,
      user,
      scope,
      onPostForwardCreated,
      onRequestLapsed,
    );

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
    throw const IdDuplicateException(
      description: 'Could not allocate public_key',
    );
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
  }) => _database.withTransaction<UserEntity>(
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
    InvitedPostForwardCreated? onPostForwardCreated,
    InvitedRequestLapsed? onRequestLapsed,
  }) => _database.withJoinedTransaction<UserEntity>(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingleOrNull();
    if (invitation == null) {
      throw const InvitationWrongException(
        description: 'Invitation not found',
      );
    }
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
        reason: InvitationWrongReason.used,
      );
    }
    if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(
        description: 'Invitation expired!',
        reason: InvitationWrongReason.expired,
      );
    }

    final scope = await _lockInvitedSignupScope(invitation);

    final user = await _createUserWithCredential(
      type: type,
      identifier: identifier,
      displayName: displayName,
      handle: handle,
      publicData: publicData,
      contacts: contacts,
    );
    final changedRowCount =
        await (_database.update(_database.invitations)..where(
              (t) => t.id.equals(invitationId) & t.invitedId.isNull(),
            ))
            .write(
              InvitationsCompanion(
                invitedId: Value(user.id),
                inviteOrigin: Value(InviteOrigin.newAccount.key),
                acceptedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
    if (changedRowCount == 0) {
      throw const InvitationWrongException(
        description: 'Can`t update invitation!',
      );
    }

    final descendantUser = await _database.managers.users
        .filter((e) => e.id(user.id))
        .getSingle();

    await _finishInvitedSignup(
      invitation,
      descendantUser,
      scope,
      onPostForwardCreated,
      onRequestLapsed,
    );

    return user;
  });

  Future<void> _finishInvitedSignup(
    Invitation invitation,
    User user,
    ({BeaconEntity beacon, bool canForward})? scope,
    InvitedPostForwardCreated? onPostForwardCreated,
    InvitedRequestLapsed? onRequestLapsed,
  ) async {
    final beacon = scope?.beacon;
    var canForward = scope?.canForward ?? false;
    final parentEdgeId = invitation.parentForwardEdgeId;
    if (canForward &&
        parentEdgeId != null &&
        !await _lockActiveInviteParentChain(parentEdgeId)) {
      if (beacon?.kind == BeaconKind.post) {
        throw IdNotFoundException(id: parentEdgeId);
      }
      canForward = false;
    }

    await _upsertInviteContact(
      viewerId: invitation.userId,
      subjectId: user.id,
      addresseeName: invitation.addresseeName,
    );
    await _inviteSeedPrompt.insertPending(
      inviterId: invitation.userId,
      inviteeId: user.id,
    );
    final ancestorUser = await _database.managers.users
        .filter((e) => e.id(invitation.userId))
        .getSingle();
    final forwardCreated =
        canForward &&
        beacon != null &&
        await _materializeBeaconInviteForward(
          beaconId: beacon.id,
          senderId: invitation.userId,
          recipientId: user.id,
          parentForwardEdgeId: parentEdgeId,
        );
    await _applyReciprocalTrustEdges(
      user.id,
      invitation.userId,
      InviteOrigin.newAccount,
    );
    // The inherited-block trigger can also lock the trust generation. Record
    // genealogy once both vote subject counters are already locked.
    await _inviteGenealogyRepository.recordSignupEdge(
      ancestorUserId: invitation.userId,
      ancestorUserCreatedAt: ancestorUser.createdAt.dateTime,
      descendantUserId: user.id,
      descendantUserCreatedAt: user.createdAt.dateTime,
      invitationId: invitation.id,
    );
    if (beacon != null && forwardCreated) {
      await onPostForwardCreated?.call(beacon, user.id);
    } else if (beacon != null && !canForward) {
      onRequestLapsed?.call(beacon.title);
    }
  }

  @override
  Future<UserEntity> getById(String id) => _database.managers.users
      .filter((e) => e.id(id))
      .getSingle()
      .then(userModelToEntity);

  @override
  Future<UserEntity> getByPublicKey(String publicKey) => _database
      .managers
      .users
      .filter((e) => e.publicKey(publicKey))
      .getSingle()
      .then(userModelToEntity);

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

  @override
  Future<List<AccountCredentialEntity>> listCredentials({
    required String accountId,
  }) => _database.managers.accountCredentials
      .filter((e) => e.accountId.id(accountId))
      .get()
      .then((rows) => rows.map(_credentialModelToEntity).toList());

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
      final existing = await _findCredentialRow(
        type: type,
        identifier: identifier,
      );
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

  @override
  Future<String> linkCredentialWithContacts({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) => _database.withWorkContext(() async {
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
      return await _database.withTransaction<String>(() async {
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
      }, actorUserId: accountId);
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
  }, actorUserId: accountId);

  @override
  Future<AccountCredentialEntity> linkCredentialToAccountStrict({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) => _database.withWorkContext(() async {
    final authoritative = AssertedContact.authoritativeOnly(contacts);

    // Idempotent: the credential is already linked to this exact account.
    final existing = await _findCredentialRow(
      type: type,
      identifier: identifier,
    );
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
      return await _database.withTransaction<AccountCredentialEntity>(() async {
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
      }, actorUserId: accountId);
    } on UniqueViolationException catch (_) {
      // Lost a race — re-resolve ownership and map to the right 409.
      final raced = await _findCredentialRow(
        type: type,
        identifier: identifier,
      );
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
  }, actorUserId: accountId);

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
  }) async =>
      (await _findCredentialRow(type: type, identifier: identifier))?.accountId;

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

  @override
  Future<void> removeCredential({
    required String accountId,
    required String credentialId,
  }) => _database.withTransaction(() async {
    // Lock the account's credential rows so concurrent removals serialize —
    // otherwise two deletes of different rows could both pass the
    // last-credential guard and leave the account with none.
    final locked = await _database
        .customSelect(
          'SELECT id FROM public.account_credential '
          r'WHERE account_id = $1 FOR UPDATE',
          variables: [Variable<String>(accountId)],
        )
        .get();
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
  }, actorUserId: accountId);

  AccountCredentialEntity _credentialModelToEntity(AccountCredential row) =>
      AccountCredentialEntity(
        id: row.id,
        accountId: row.accountId,
        type: CredentialType.fromWire(row.type),
        identifier: row.identifier,
        publicData: (row.publicData as Map?)?.cast<String, Object?>(),
        createdAt: row.createdAt.dateTime,
      );

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

  @override
  Future<void> deleteById({required String id}) =>
      _database.managers.users.filter((e) => e.id(id)).delete();

  @override
  Future<InviteAcceptance> acceptRequestInvite({
    required String invitationId,
    required String userId,
  }) => _acceptInvite(
    invitationId: invitationId,
    userId: userId,
    mode: _InviteAcceptanceMode.requestAdmission,
  );

  @override
  Future<bool> bindMutual({
    required String invitationId,
    required String userId,
    bool bindFriendship = true,
    Future<void> Function()? onForwardCreated,
  }) async {
    final result = await _acceptInvite(
      invitationId: invitationId,
      userId: userId,
      mode: bindFriendship
          ? _InviteAcceptanceMode.friendship
          : _InviteAcceptanceMode.forwardOnly,
      onForwardCreated: onForwardCreated,
    );
    return result.isConsumed;
  }

  Future<InviteAcceptance> _acceptInvite({
    required String invitationId,
    required String userId,
    required _InviteAcceptanceMode mode,
    Future<void> Function()? onForwardCreated,
  }) => _database.withJoinedTransaction(() async {
    final invitation = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .getSingleOrNull();
    if (invitation == null) {
      throw const InvitationWrongException(
        description: 'Invitation not found',
      );
    }
    if (invitation.invitedId != null) {
      throw const InvitationWrongException(
        description: 'Invitation already used!',
        reason: InvitationWrongReason.used,
      );
    } else if (invitation.createdAt.dateTime
        .add(_env.invitationTTL)
        .isBefore(DateTime.timestamp())) {
      throw const InvitationWrongException(
        description: 'Invitation expired!',
        reason: InvitationWrongReason.expired,
      );
    }

    final beaconId = invitation.beaconId;
    final parentEdgeId = invitation.parentForwardEdgeId;
    final requestId = mode == _InviteAcceptanceMode.requestAdmission
        ? beaconId ?? (throw IdNotFoundException(id: invitationId))
        : null;
    if (requestId != null) {
      // Share closure's lock through the status check and forward insert.
      await ClosureRepository(_database).lockRequest(requestId);
    }

    var chainIsLive = true;
    if (beaconId != null && parentEdgeId != null) {
      // Reserve the claim before locking the chain. A lapsed Request may
      // consume its invite even when the chain is broken.
      final claim = await _database
          .customSelect(
            'SELECT id FROM public.invitation '
            r'WHERE id = $1 AND invited_id IS NULL FOR NO KEY UPDATE',
            variables: [Variable<String>(invitationId)],
          )
          .getSingleOrNull();
      if (claim == null) return InviteAcceptance.notClaimed;
      chainIsLive = await _lockActiveInviteParentChain(parentEdgeId);
      if (!chainIsLive && requestId == null) {
        return InviteAcceptance.notClaimed;
      }
    }

    var requestLapsed = false;
    if (requestId != null) {
      final row = await _database.managers.beacons
          .filter((e) => e.id.equals(requestId))
          .getSingleOrNull();
      if (row == null || row.kind != BeaconKind.request.value) {
        throw IdNotFoundException(id: invitationId);
      }
      requestLapsed =
          !chainIsLive ||
          !await _canForwardRequestInvite(
            _inviteBeacon(row),
            issuerId: invitation.userId,
          );
    }

    // Claim the row first, atomically — everything below is a side effect
    // of a *successful* claim. A losing racer must get none of it (no
    // contact/forward/vote/trust-edge writes for an accept that didn't win).
    final changedRowCount =
        await (_database.update(_database.invitations)..where(
              (t) => t.id.equals(invitationId) & t.invitedId.isNull(),
            ))
            .write(
              InvitationsCompanion(
                invitedId: Value(userId),
                inviteOrigin: Value(InviteOrigin.existingAccount.key),
                acceptedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
    if (changedRowCount == 0) {
      return InviteAcceptance.notClaimed;
    }
    if (requestLapsed) return InviteAcceptance.requestLapsed;

    await _upsertInviteContact(
      viewerId: invitation.userId,
      subjectId: userId,
      addresseeName: invitation.addresseeName,
    );

    final forwardCreated =
        beaconId != null &&
        await _materializeBeaconInviteForward(
          beaconId: beaconId,
          senderId: invitation.userId,
          recipientId: userId,
          parentForwardEdgeId: parentEdgeId,
        );

    if (mode == _InviteAcceptanceMode.friendship) {
      await _applyReciprocalTrustEdges(
        invitation.userId,
        userId,
        InviteOrigin.existingAccount,
      );
    }
    if (forwardCreated) await onForwardCreated?.call();

    return InviteAcceptance.accepted;
  });

  Future<void> _applyReciprocalTrustEdges(
    String userA,
    String userB,
    InviteOrigin origin,
  ) async {
    final subjects = [userA, userB]..sort();
    final existingInvite = origin == InviteOrigin.existingAccount;
    final onConflict = existingInvite
        ? ' ON CONFLICT (subject, object) DO NOTHING'
        : '';
    // Both subject counters must be locked before the statement trigger
    // advances the trust generation.
    await _database.customStatement(
      'INSERT INTO public.vote_user (subject, object, amount, from_existing_invite) '
      r'VALUES ($1, $2, 1, $3), ($2, $1, 1, $3)'
      '$onConflict',
      [...subjects, existingInvite],
    );
    const projection = r'SELECT public.trust_project_pair($1, $2)';
    await _database.customStatement(projection, subjects);
    await _database.customStatement(projection, subjects.reversed.toList());
  }
}
