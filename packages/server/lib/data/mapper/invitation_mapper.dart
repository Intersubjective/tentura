import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../database/tentura_db.dart';
import 'user_mapper.dart';

InvitationEntity invitationModelToEntity(
  Invitation model, {
  required User issuer,
  User? invited,
}) => InvitationEntity(
  id: model.id,
  issuer: userModelToEntity(issuer),
  invited: invited == null ? null : userModelToEntity(invited),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
);
