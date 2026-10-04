import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/post_lock_port.dart';

import '../database/tentura_db.dart';

@Injectable(as: PostLockPort)
class PostLockRepository implements PostLockPort {
  const PostLockRepository(this._database);

  final TenturaDb _database;

  // Same key as `BeaconHierarchyRepository.lockMutationScope`.
  static const _hierarchyScopeKey = 'tentura.beacon_hierarchy.v1';

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    await _database.customStatement(
      r'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [_hierarchyScopeKey],
    );
    await _database.customStatement(
      r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
      [beaconId],
    );
    await _database.customStatement(
      r'SELECT 1 FROM public.beacon WHERE id = $1 FOR UPDATE',
      [beaconId],
    );
  }
}
