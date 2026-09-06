import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/polling_act_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';

@GenerateMocks([
  PollingActRepositoryPort,
  PollingRepositoryPort,
  BeaconRoomRepositoryPort,
])
void main() {}
