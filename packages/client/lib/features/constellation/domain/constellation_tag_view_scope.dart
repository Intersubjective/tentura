import 'package:meta/meta.dart';

import 'constellation_tag_filter.dart';
import 'entity/constellation_field.dart';

/// What the tag view does with everyone outside the viewed tags.
enum ConstellationTagViewOthers { hide, dots, asIs }

/// Who the tag view shows ([memberIds]) and what happens to the rest: exactly
/// one of [hiddenIds], [dotIds] and [othersAsIsIds] holds every non-member.
@immutable
class ConstellationTagViewScope {
  const ConstellationTagViewScope({
    required this.memberIds,
    this.hiddenIds = const {},
    this.dotIds = const {},
    this.othersAsIsIds = const {},
  });

  final Set<String> memberIds;
  final Set<String> hiddenIds;
  final Set<String> dotIds;
  final Set<String> othersAsIsIds;
}

/// The tag view in force: the viewed [filter], the choice for [others] and
/// the resulting [scope].
@immutable
class ConstellationTagView {
  const ConstellationTagView({
    required this.filter,
    required this.others,
    required this.scope,
  });

  final ConstellationTagFilter filter;
  final ConstellationTagViewOthers others;
  final ConstellationTagViewScope scope;
}

/// The tag view shows the people [filter] matches (own and automatic tags
/// alike); [ownTagIdsOf] comes from the tag store index.
ConstellationTagViewScope resolveConstellationTagViewScope({
  required ConstellationTagFilter filter,
  required Iterable<ConstellationPerson> people,
  required Set<String> Function(String personId) ownTagIdsOf,
  required ConstellationTagViewOthers others,
}) {
  final members = <String>{};
  final rest = <String>{};
  for (final person in people) {
    (filter.matches(person, ownTagIds: ownTagIdsOf(person.id))
            ? members
            : rest)
        .add(person.id);
  }
  return switch (others) {
    ConstellationTagViewOthers.hide => ConstellationTagViewScope(
      memberIds: members,
      hiddenIds: rest,
    ),
    ConstellationTagViewOthers.dots => ConstellationTagViewScope(
      memberIds: members,
      dotIds: rest,
    ),
    ConstellationTagViewOthers.asIs => ConstellationTagViewScope(
      memberIds: members,
      othersAsIsIds: rest,
    ),
  };
}

/// "Open tag view" is offered only while both feature flags are on.
bool constellationTagViewEntryAvailable({
  required bool peopleTagsEnabled,
  required bool arrangeV2Enabled,
}) => peopleTagsEnabled && arrangeV2Enabled;
