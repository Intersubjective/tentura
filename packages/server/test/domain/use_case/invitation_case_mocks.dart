import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';

@GenerateMocks([
  InvitationRepositoryPort,
  UserRepositoryPort,
  BeaconRepositoryPort,
  VoteUserFriendshipLookup,
])
void main() {}
