import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/capability_own_evidence_port.dart';
import 'package:tentura_server/domain/port/pair_block_query_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

@GenerateMocks([
  WitnessWindowPort,
  CapabilityCellPort,
  CapabilityOwnEvidencePort,
  RoutingMutePort,
  PairBlockQueryPort,
  PersonVisibilityRepositoryPort,
  UserBlockRepositoryPort,
])
void main() {}
