import 'package:mockito/annotations.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';

@GenerateMocks([
  BeaconRepository,
  CommitmentRepository,
  CoordinationRepository,
  InboxRepository,
])
void main() {}
