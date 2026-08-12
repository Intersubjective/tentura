import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/band_candidate_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

@GenerateMocks([
  BandCandidatePort,
  BeaconRepositoryPort,
])
void main() {}
