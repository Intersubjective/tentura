import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';
import '../mapper/user_mapper.dart';

export 'package:tentura_server/domain/entity/user_entity.dart';

@Singleton(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class UserRepository {
  const UserRepository(
    this._env,
    this._database,
  );

  final Env _env;

  final TenturaDb _database;

  //
  //
  Future<UserEntity> create({
    required String publicKey,
    required String title,
  }) => _database.managers.users
      .createReturning((o) => o(title: title, publicKey: publicKey))
      .then(userModelToEntity);

  // TBD: move to SQL
  //
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String title,
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
      (o) => o(title: title, publicKey: publicKey),
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

    return userModelToEntity(user);
  });

  //
  //
  Future<UserEntity> getById(String id) => _database.managers.users
      .filter((e) => e.id(id))
      .getSingle()
      .then(userModelToEntity);

  //
  //
  Future<UserEntity> getByPublicKey(String publicKey) => _database
      .managers
      .users
      .filter((e) => e.publicKey(publicKey))
      .getSingle()
      .then(userModelToEntity);

  //
  //
  Future<void> update({
    required String id,
    String? title,
    String? description,
    String? imageId,
    bool dropImage = false,
  }) => _database.managers.users
      .filter((e) => e.id(id))
      .update(
        (o) => o(
          title: Value.absentIfNull(title),
          description: Value.absentIfNull(description),
          imageId: dropImage
              ? const Value(null)
              : imageId == null
              ? const Value.absent()
              : Value(UuidValue.fromString(imageId)),
        ),
      );

  //
  //
  Future<void> deleteById({required String id}) =>
      _database.managers.users.filter((e) => e.id(id)).delete();

  //
  // TBD: move to SQL
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

    return invitationsDeletedCount == 1;
  });
}
