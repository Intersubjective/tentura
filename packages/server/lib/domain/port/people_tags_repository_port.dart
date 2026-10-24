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
}
