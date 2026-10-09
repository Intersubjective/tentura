import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

/// Adapts a fake's `userPublicRecordsByIds` to
/// `UserProfileBatchLookup.constellationProfilesByIds`.
Future<Map<String, ConstellationPeerRecord>> constellationProfilesFromRecords(
  UserProfileBatchLookup lookup,
  Iterable<String> ids,
) async {
  final records = await lookup.userPublicRecordsByIds(
    ids: ids,
    reciprocalPeerIds: const {},
  );
  return {
    for (final entry in records.entries)
      entry.key: ConstellationPeerRecord(
        id: entry.value.id,
        displayName: entry.value.displayName,
        handle: entry.value.handle,
        image: entry.value.image,
      ),
  };
}
