import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'people_tag_profiles.dart';

/// Screen-reader label for an inherited own-tag membership on [personId].
String peopleTagsInheritedSemantics(
  L10n l10n,
  PeopleTagsCase tags,
  PeopleTagProfiles profiles,
  String tagId,
  String personId,
) {
  final inviterId = tags.inheritedFrom(tagId, personId);
  if (inviterId == null) {
    return l10n.peopleTagsInheritedChipSemanticsUnknownInviter;
  }
  return l10n.peopleTagsInheritedChipSemantics(profiles.displayName(inviterId));
}
