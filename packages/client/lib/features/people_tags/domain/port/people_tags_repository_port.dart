import '../entity/people_tags_entities.dart';

abstract interface class PeopleTagsRepositoryPort {
  Future<List<PersonTag>> personTags();

  Future<PersonTagsOf> personTagsOf(String personId);

  Future<List<PersonTagMembers>> personTagMemberships();

  Future<List<PersonAutoTag>> personAutoTags();

  Future<List<String>> personAutoTagMembers(int kind);

  Future<PersonTagSuggestionState> personTagSuggestionState();

  Future<PersonTag> personTagCreate({
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,

    /// Snapshot the people of this automatic tag kind into the new tag.
    int? fromAutoKind,

    /// Snapshot the other members of this Request into the new tag.
    String? fromBeaconId,
  });

  Future<PersonTag> personTagUpdate({
    required String id,
    required String clientOpId,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  });

  Future<PersonTagSnapshot> personTagDelete({
    required String id,
    required String clientOpId,
  });

  Future<PersonTag> personTagRestore({
    required PersonTagSnapshot snapshot,
    required String clientOpId,
  });

  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  });

  Future<PersonAutoTag> personAutoTagPrefSet({
    required int kind,
    required bool showInFilters,
  });

  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  });
}
