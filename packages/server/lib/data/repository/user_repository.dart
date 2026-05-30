import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
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
  const UserRepository(
    this._env,
    this._database,
  );

  final Env _env;

  final TenturaDb _database;

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
      // Unique (type, identifier) index — the pair is already linked (on this
      // or another account). Conflict policy: refuse, never auto-merge.
      throw const CredentialConflictException();
    }
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

    final invitationsDeletedCount = await _database.managers.invitations
        .filter((e) => e.id(invitationId))
        .delete();

    await _database.managers.voteUsers.bulkCreate(
      (o) => [
        o(subject: invitation.userId, object: userId, amount: 1),
        o(subject: userId, object: invitation.userId, amount: 1),
      ],
      mode: InsertMode.insertOrIgnore,
      onConflict: DoNothing(),
    );

    if (invitation.beaconId != null) {
      await _database.into(_database.inboxItems).insert(
        InboxItemsCompanion.insert(
          userId: userId,
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

    return invitationsDeletedCount == 1;
  });
}
