import 'package:tentura_server/domain/entity/person_tag.dart';

/// An owner's private people tags (m0261). Every mutation is one transaction
/// and idempotent by `(ownerId, clientOpId)`: a repeat with the same
/// the fingerprint returns the stored result, a different one throws
/// opIdReused.
abstract interface class PeopleTagsRepositoryPort {
  Future<List<PersonTag>> list(String ownerId);

  /// [color] defaults to the number of own tags modulo 8.
  Future<PersonTag> create({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String name,
    required String glyph,
    int? color,
  });

  Future<PersonTag> update({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  });

  Future<PersonTagSnapshot> delete({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
  });

  /// Recreates the snapshot's tag with the same id.
  Future<PersonTag> restore({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required PersonTagSnapshot snapshot,
  });

  /// Applies [ops] in order in one transaction. Adding someone a block hides
  /// is skipped without a trace. Throws tagNotFound for a tag that is not
  /// the owner's, invalidTag for the owner or an unknown person, and
  /// memberLimitReached when a tag would end over 1000 members.
  Future<void> applyMembers({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required List<PersonTagMemberOp> ops,
  });

  /// Every own tag with its members, blocked people left out.
  Future<List<PersonTagMembers>> memberships(String ownerId);

  /// Ids of the owner's tags that [personId] is in, in tag order.
  Future<List<String>> tagIdsOf(String ownerId, String personId);
}
