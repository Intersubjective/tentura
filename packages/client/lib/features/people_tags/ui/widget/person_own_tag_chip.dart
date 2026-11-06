import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'people_tag_profiles.dart';
import 'people_tags_inherited.dart';

/// Own tag [tag] on [personId]: inherited ✦, optional Keep, optional ×.
class PersonOwnTagChip extends StatelessWidget {
  const PersonOwnTagChip({
    required this.tag,
    required this.personId,
    required this.profiles,
    this.onRemove,
    this.onKeep,
    this.maxWidth,
    this.selected = false,
    super.key,
  });

  final PersonTag tag;
  final String personId;
  final PeopleTagProfiles profiles;
  final VoidCallback? onRemove;
  final VoidCallback? onKeep;
  final double? maxWidth;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tags = GetIt.I<PeopleTagsCase>();
    final inherited = tags.isInheritedMember(tag.id, personId);
    return PersonTagChip(
      glyph: tag.glyph,
      name: tag.name,
      colorIndex: tag.color,
      maxWidth: maxWidth,
      selected: selected,
      showInheritedMarker: inherited,
      semanticsLabel: inherited
          ? peopleTagsInheritedSemantics(l10n, tags, profiles, tag.id, personId)
          : null,
      tooltipMessage: inherited
          ? peopleTagsInheritedSemantics(l10n, tags, profiles, tag.id, personId)
          : null,
      onKeep: inherited ? onKeep : null,
      keepLabel: l10n.peopleTagsInheritedKeep,
      keepSemanticsLabel: l10n.peopleTagsInheritedKeepSemantics(tag.name),
      onRemove: onRemove,
    );
  }
}
