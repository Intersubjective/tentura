import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/forward_candidate_context_repository_port.dart';

@Injectable(
  as: ForwardCandidateContextRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ForwardCandidateContextRepositoryMock extends Mock
    implements ForwardCandidateContextRepositoryPort {}
