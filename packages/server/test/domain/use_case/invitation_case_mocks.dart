import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

@GenerateMocks([
  InvitationRepositoryPort,
  UserContactRepositoryPort,
  UserRepositoryPort,
  BeaconRepositoryPort,
  VoteUserFriendshipLookupPort,
  VerifiedContactRepositoryPort,
])
void main() {}
