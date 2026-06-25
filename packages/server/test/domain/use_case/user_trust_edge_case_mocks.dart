import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';

@GenerateMocks([UserRepositoryPort, UserTrustEdgeRepositoryPort])
void main() {}
