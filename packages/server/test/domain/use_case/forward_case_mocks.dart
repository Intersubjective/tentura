import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';

@GenerateMocks([
  ForwardEdgeRepositoryPort,
  CommitmentRepositoryPort,
  InboxRepositoryPort,
  PersonCapabilityEventRepositoryPort,
])
void main() {}
