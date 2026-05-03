import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

@GenerateMocks([
  BeaconRepositoryPort,
  CommitmentRepositoryPort,
  CoordinationRepositoryPort,
  InboxRepositoryPort,
  PersonCapabilityEventRepositoryPort,
  BeaconRoomRepository,
  VoteUserFriendshipLookup,
  BeaconRoomPushService,
])
void main() {}
