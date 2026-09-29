import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/pair_block_query_port.dart';

@Injectable(
  as: PairBlockQueryPort,
  env: [Environment.test],
  order: 1,
)
class PairBlockQueryRepositoryMock implements PairBlockQueryPort {
  @override
  Future<Set<(String, String)>> blockedPairsAmong({
    required Set<String> userIds,
  }) => Future.value(const {});
}
