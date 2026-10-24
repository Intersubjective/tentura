import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';

@Injectable(
  as: PeopleTagsRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class PeopleTagsRepositoryMock implements PeopleTagsRepositoryPort {
  @override
  Future<List<PersonTag>> list(String ownerId) => throw UnimplementedError();

  @override
  Future<PersonTag> create({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String name,
    required String glyph,
    int? color,
  }) => throw UnimplementedError();

  @override
  Future<PersonTag> update({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) => throw UnimplementedError();

  @override
  Future<PersonTagSnapshot> delete({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String id,
  }) => throw UnimplementedError();

  @override
  Future<PersonTag> restore({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required PersonTagSnapshot snapshot,
  }) => throw UnimplementedError();
}
