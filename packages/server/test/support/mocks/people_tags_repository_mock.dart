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
    int? fromAutoKind,
    String? fromBeaconId,
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

  @override
  Future<void> applyMembers({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required List<PersonTagMemberOp> ops,
  }) => throw UnimplementedError();

  @override
  Future<List<PersonTagMembers>> memberships(String ownerId) =>
      throw UnimplementedError();

  @override
  Future<List<String>> tagIdsOf(String ownerId, String personId) =>
      throw UnimplementedError();

  @override
  Future<List<PersonAutoTagSummary>> autoTags(String ownerId) =>
      throw UnimplementedError();

  @override
  Future<PersonAutoTagSummary> setAutoTagPref({
    required String ownerId,
    required int kind,
    required bool showInFilters,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> autoTagMembers(String ownerId, int kind) =>
      throw UnimplementedError();

  @override
  Future<List<PersonAutoTagOf>> autoTagsOf(String ownerId, String personId) =>
      throw UnimplementedError();

  @override
  Future<PersonTagSuggestionState> suggestionState(String ownerId) =>
      throw UnimplementedError();

  @override
  Future<PersonTagSuggestionState> recordSuggestion({
    required String ownerId,
    required String clientOpId,
    required String fingerprint,
    required String outcome,
  }) => throw UnimplementedError();
}
