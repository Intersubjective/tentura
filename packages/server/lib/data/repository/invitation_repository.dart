import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/invitation_mapper.dart';

@Injectable(
  as: InvitationRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class InvitationRepository implements InvitationRepositoryPort {
  const InvitationRepository(this._database);

  final TenturaDb _database;

  @override
  Future<InvitationEntity> create({
    required String issuerId,
    String? beaconId,
  }) async {
    final row = await _database.managers.invitations.createReturning(
      (o) => o(
        userId: issuerId,
        beaconId: Value.absentIfNull(beaconId),
      ),
    );
    final issuer = await _database.managers.users
        .filter((e) => e.id(issuerId))
        .getSingle();
    final issuerImage = issuer.imageId == null
        ? null
        : await _database.managers.images
            .filter((e) => e.id(issuer.imageId!))
            .getSingleOrNull();
    return invitationModelToEntity(
      row,
      issuer: issuer,
      issuerImage: issuerImage,
    );
  }

  @override
  Future<InvitationEntity?> getById({
    required String invitationId,
  }) async {
    final result = await _database.managers.invitations
        .filter((f) => f.id(invitationId))
        .withReferences((p) => p(userId: true, invitedId: true))
        .getSingleOrNull();
    if (result == null) {
      return null;
    }
    final issuer = await result.$2.userId.getSingle();
    final invited = await result.$2.invitedId?.getSingleOrNull();
    final issuerImgId = issuer.imageId;
    final issuerImage = issuerImgId == null
        ? null
        : await _database.managers.images
            .filter((e) => e.id(issuerImgId))
            .getSingleOrNull();
    final invitedImgId = invited?.imageId;
    final invitedImage = invitedImgId == null
        ? null
        : await _database.managers.images
            .filter((e) => e.id(invitedImgId))
            .getSingleOrNull();
    return invitationModelToEntity(
      result.$1,
      issuer: issuer,
      invited: invited,
      issuerImage: issuerImage,
      invitedImage: invitedImage,
    );
  }

  @override
  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  }) async =>
      await _database.managers.invitations
          .filter((e) => e.id(invitationId) & e.userId.id(userId))
          .delete() ==
      1;
}
