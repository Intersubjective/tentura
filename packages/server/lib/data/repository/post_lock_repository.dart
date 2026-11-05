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
    await _lockPost(beaconId);
  }

  @override
  Future<void> lockForPostDelivery(
    String beaconId, {
    required String senderId,
  }) async {
    await _database.customStatement(
      r'SELECT pg_advisory_xact_lock_shared(hashtextextended($1, 0))',
      ['tentura.user_block.v1:$senderId'],
    );
    await _lockPost(beaconId);
  }

  Future<void> _lockPost(String beaconId) async {
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
