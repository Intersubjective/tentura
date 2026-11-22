import 'package:tentura_server/domain/entity/invitation_entity.dart';

import 'package:tentura_server/data/repository/mock/data/users.dart';

final kInvitationFromThorin = InvitationEntity(
  id: 'I286f94380611',
  issuer: kUserThorin,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final kInvitationsById = <String, InvitationEntity>{
  kInvitationFromThorin.id: kInvitationFromThorin,
};
