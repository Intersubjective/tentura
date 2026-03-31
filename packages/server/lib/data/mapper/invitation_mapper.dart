import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../database/tentura_db.dart';
import 'user_mapper.dart';

InvitationEntity invitationModelToEntity(
  Invitation model, {
  required User issuer,
  User? invited,
  Image? issuerImage,
  Image? invitedImage,
}) => InvitationEntity(
  id: model.id,
  issuer: userModelToEntity(issuer, image: issuerImage),
  invited: invited == null ? null : userModelToEntity(invited, image: invitedImage),
  createdAt: model.createdAt.dateTime,
  updatedAt: model.updatedAt.dateTime,
);
