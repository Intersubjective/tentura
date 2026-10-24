import 'package:freezed_annotation/freezed_annotation.dart';

part 'people_tags_entities.freezed.dart';

/// An owner's private tag; the counts are derived by the server.
@freezed
abstract class PersonTag with _$PersonTag {
  const factory PersonTag({
    required String id,
    required String name,
    required String glyph,
    required int color,
    required int ord,
    @Default(0) int count,
    @Default(0) int countOffField,
  }) = _PersonTag;

  const PersonTag._();
}

/// The people in one own tag.
@freezed
abstract class PersonTagMembers with _$PersonTagMembers {
  const factory PersonTagMembers({
    required String tagId,
    required List<String> personIds,
  }) = _PersonTagMembers;

  const PersonTagMembers._();
}

/// An automatic tag list entry: how many people, and the filter switch.
@freezed
abstract class PersonAutoTag with _$PersonAutoTag {
  const factory PersonAutoTag({
    required int kind,
    required int count,
    required bool showInFilters,
  }) = _PersonAutoTag;

  const PersonAutoTag._();
}

/// An automatic tag one person carries; `direction` is set for invited only.
@freezed
abstract class PersonAutoTagOf with _$PersonAutoTagOf {
  const factory PersonAutoTagOf({
    required int kind,
    required int n,
    required int direction,
  }) = _PersonAutoTagOf;

  const PersonAutoTagOf._();
}

/// The owner's tags a person is in: own tag ids and automatic tags.
@freezed
abstract class PersonTagsOf with _$PersonTagsOf {
  const factory PersonTagsOf({
    required List<String> own,
    required List<PersonAutoTagOf> auto,
  }) = _PersonTagsOf;

  const PersonTagsOf._();
}

@freezed
abstract class PersonTagSuggestionState with _$PersonTagSuggestionState {
  const factory PersonTagSuggestionState({
    required bool canSuggest,
    required bool disabled,
    DateTime? silencedUntil,
  }) = _PersonTagSuggestionState;

  const PersonTagSuggestionState._();
}

/// A deleted tag with its members, enough to restore it (Undo).
@freezed
abstract class PersonTagSnapshot with _$PersonTagSnapshot {
  const factory PersonTagSnapshot({
    required PersonTag tag,
    required List<String> memberIds,
    required List<int> sources,
  }) = _PersonTagSnapshot;

  const PersonTagSnapshot._();
}

/// One add or remove in a batch of membership edits.
@freezed
abstract class PersonTagMemberOp with _$PersonTagMemberOp {
  const factory PersonTagMemberOp({
    required String tagId,
    required String personId,
    required bool add,

    /// Membership source; 0 is a manual edit.
    @Default(0) int source,
  }) = _PersonTagMemberOp;

  const PersonTagMemberOp._();
}
