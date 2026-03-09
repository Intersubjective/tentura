import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/invitation_mapper.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class InvitationRepository {
  const InvitationRepository(this._database);

  final TenturaDb _database;

  Future<InvitationEntity?> getById({
    required String invitationId,
  }) async {
    final result = await _database.managers.invitations
        .filter((f) => f.id(invitationId))
        .withReferences((p) => p(userId: true, invitedId: true))
        .getSingleOrNull();
    return result == null
        ? null
        : invitationModelToEntity(
            result.$1,
            issuer: await result.$2.userId.getSingle(),
            invited: await result.$2.invitedId?.getSingleOrNull(),
          );
  }

  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  }) async =>
      await _database.managers.invitations
          .filter((e) => e.id(invitationId) & e.userId.id(userId))
          .delete() ==
      1;
}
