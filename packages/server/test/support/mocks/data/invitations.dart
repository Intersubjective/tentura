import 'package:tentura_server/domain/entity/invitation_entity.dart';

import 'users.dart';

final kInvitationFromThorin = InvitationEntity(
  id: 'I286f94380611',
  issuer: kUserThorin,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final kInvitationsById = <String, InvitationEntity>{
  kInvitationFromThorin.id: kInvitationFromThorin,
};
