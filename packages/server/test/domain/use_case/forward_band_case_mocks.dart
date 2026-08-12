import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/band_candidate_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

@GenerateMocks([
  BandCandidatePort,
  BeaconRepositoryPort,
  BeaconAccessGuard,
])
void main() {}
