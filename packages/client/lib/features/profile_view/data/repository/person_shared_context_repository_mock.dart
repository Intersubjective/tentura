import 'package:injectable/injectable.dart';

import '../../domain/port/person_shared_context_port.dart';

@Singleton(as: PersonSharedContextPort, env: [Environment.test])
final class PersonSharedContextRepositoryMock
    implements PersonSharedContextPort {
  @override
  Future<List<PersonSharedContext>> fetchSharedContexts(String userId) async =>
      const [];
}
