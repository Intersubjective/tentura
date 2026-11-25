import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../exception.dart';
import '../exception_codes.dart';

/// One of an owner's private tags over other people (#699).
@immutable
final class PersonTag {
  const PersonTag({
    required this.id,
    required this.name,
    required this.glyph,
    required this.color,
    required this.ord,
    this.count = 0,
    this.countOffField = 0,
  });

  factory PersonTag.fromJson(Map<String, dynamic> json) => PersonTag(
    id: json['id']! as String,
    name: json['name']! as String,
    glyph: json['glyph']! as String,
    color: json['color']! as int,
    ord: json['ord']! as int,
    count: json['count'] as int? ?? 0,
    countOffField: json['countOffField'] as int? ?? 0,
  );

  final String id;
  final String name;
  final String glyph;
  final int color;
  final int ord;

  /// Members not hidden by a block, and of those the ones off the owner's
  /// Field. Derived on read: not part of [toJson] and not compared.
  final int count;
  final int countOffField;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'glyph': glyph,
    'color': color,
    'ord': ord,
  };

  /// The GraphQL `PersonTag` object: [toJson] plus the derived counts.
  Map<String, dynamic> toGraphQL() => {
    ...toJson(),
    'count': count,
    'countOffField': countOffField,
  };

  @override
  bool operator ==(Object other) =>
      other is PersonTag &&
      other.id == id &&
      other.name == name &&
      other.glyph == glyph &&
      other.color == color &&
      other.ord == ord;

  @override
  int get hashCode => Object.hash(id, name, glyph, color, ord);
}

enum PersonTagSnapshotMemberKind { person, phantom }

/// The identity and source of one membership before deletion.
final class PersonTagSnapshotMember {
  const PersonTagSnapshotMember({
    required this.kind,
    required this.id,
    required this.membershipId,
    required this.source,
  });

  factory PersonTagSnapshotMember._fromJson(Object? json, String idKey) {
    if (json is! Map) throw _invalidSnapshot();
    if ((json, json[idKey])
        case (
          {
            'kind': final String kind,
            'id': final String id,
            'source': final int source,
          },
          final String membershipId,
        )
        when Uuid.isValidUUID(
          fromString: membershipId,
          validationMode: ValidationMode.nonStrict,
        )) {
      return PersonTagSnapshotMember(
        kind: switch (kind) {
          'person' => PersonTagSnapshotMemberKind.person,
          'phantom' => PersonTagSnapshotMemberKind.phantom,
          _ => throw _invalidSnapshot(),
        },
        id: id,
        membershipId: membershipId,
        source: source,
      );
    }
    throw _invalidSnapshot();
  }

  final PersonTagSnapshotMemberKind kind;
  final String id;
  final String membershipId;
  final int source;

  Map<String, Object> _toJson(String idKey) => {
    'kind': kind.name,
    'id': id,
    idKey: membershipId,
    'source': source,
  };
}

PeopleTagsException _invalidSnapshot() => PeopleTagsException(
  peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
);

/// What a delete removed, enough to restore the tag and its memberships.
final class PersonTagSnapshot {
  PersonTagSnapshot({
    required this.tag,
    required List<PersonTagSnapshotMember> members,
  }) : members = List.unmodifiable(members);

  factory PersonTagSnapshot.fromJson(Object? json, {bool stored = false}) {
    if (json case {
      'tag': final Map<String, dynamic> tag,
      'members': final List<Object?> members,
    }) {
      return PersonTagSnapshot(
        tag: PersonTag.fromJson(tag),
        members: [
          for (final member in members)
            PersonTagSnapshotMember._fromJson(
              member,
              stored ? 'membership_id' : 'membershipId',
            ),
        ],
      );
    }
    throw _invalidSnapshot();
  }

  final PersonTag tag;
  final List<PersonTagSnapshotMember> members;

  /// Keep the persisted operation results and restore fingerprints stable.
  Map<String, dynamic> toJson() => {
    'tag': tag.toJson(),
    'members': [for (final member in members) member._toJson('membership_id')],
  };

  /// The delete response and replay record retain the pre-delete counts.
  Map<String, dynamic> toGraphQL() => {
    'tag': tag.toGraphQL(),
    'members': [for (final member in members) member._toJson('membershipId')],
  };
}

/// The people in one of the owner's tags, blocked people left out.
final class PersonTagMembers {
  const PersonTagMembers({
    required this.tagId,
    required this.personIds,
    this.inherited = const [],
  });

  final String tagId;
  final List<String> personIds;

  /// Members who joined by inheriting the tag from their inviter.
  final List<PersonTagInherited> inherited;

  Map<String, dynamic> toJson() => {
    'tagId': tagId,
    'personIds': personIds,
    'inherited': [for (final i in inherited) i.toJson()],
  };
}

/// A member put in a tag automatically, with their direct inviter (null when
/// the invite record is gone).
final class PersonTagInherited {
  const PersonTagInherited({required this.personId, this.inviterId});

  final String personId;
  final String? inviterId;

  Map<String, dynamic> toJson() => {
    'personId': personId,
    'inviterId': inviterId,
  };
}

/// One add, remove or keep of a person in a tag, with the add's `source`.
/// A keep turns an inherited member into a manual one.
final class PersonTagMemberOp {
  const PersonTagMemberOp({
    required this.tagId,
    required this.personId,
    required this.add,
    required this.source,
    this.keep = false,
  });

  final String tagId;
  final String personId;
  final bool add;
  final int source;
  final bool keep;
}

/// One automatic tag the owner has: how many people, and the Field filter
/// row switch.
final class PersonAutoTagSummary {
  const PersonAutoTagSummary({
    required this.kind,
    required this.count,
    required this.showInFilters,
  });

  final int kind;
  final int count;
  final bool showInFilters;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'count': count,
    'showInFilters': showInFilters,
  };
}

/// An automatic tag one person carries for the owner.
final class PersonAutoTagOf {
  const PersonAutoTagOf({
    required this.kind,
    required this.n,
    required this.direction,
  });

  final int kind;
  final int n;
  final int direction;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'n': n,
    'direction': direction,
  };
}

/// Whether the "Tag them?" prompt may be shown to the owner.
final class PersonTagSuggestionState {
  const PersonTagSuggestionState({
    required this.canSuggest,
    required this.disabled,
    this.silencedUntil,
  });

  factory PersonTagSuggestionState.fromJson(Map<String, dynamic> json) =>
      PersonTagSuggestionState(
        canSuggest: json['canSuggest']! as bool,
        disabled: json['disabled']! as bool,
        silencedUntil: json['silencedUntil'] == null
            ? null
            : DateTime.parse(json['silencedUntil']! as String).toUtc(),
      );

  final bool canSuggest;
  final bool disabled;
  final DateTime? silencedUntil;

  /// The GraphQL object; `silencedUntil` stays a [DateTime] for `graphQLDate`.
  Map<String, dynamic> toGraphQL() => {
    'canSuggest': canSuggest,
    'silencedUntil': silencedUntil,
    'disabled': disabled,
  };

  Map<String, dynamic> toJson() => {
    'canSuggest': canSuggest,
    'silencedUntil': silencedUntil?.toUtc().toIso8601String(),
    'disabled': disabled,
  };
}
