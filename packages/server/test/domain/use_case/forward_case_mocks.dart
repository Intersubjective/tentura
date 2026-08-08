import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

@GenerateMocks([
  BeaconRepositoryPort,
  ForwardAttributionRepositoryPort,
  ForwardEdgeRepositoryPort,
  HelpOfferRepositoryPort,
  InboxRepositoryPort,
  PersonCapabilityEventRepositoryPort,
  PersonVisibilityRepositoryPort,
])
void main() {}
