import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// Batch-friendly user profile reads (display fields, public GraphQL shape).
abstract interface class UserProfileBatchLookup {
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids);

  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
  });
}
