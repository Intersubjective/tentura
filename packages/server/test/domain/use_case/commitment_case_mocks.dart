import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';

@GenerateMocks([
  BeaconRepositoryPort,
  CommitmentRepositoryPort,
  CoordinationRepositoryPort,
  InboxRepositoryPort,
])
void main() {}
