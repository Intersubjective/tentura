import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

/// One person of a tag; [trailing] is the × of an own tag.
class PeopleTagPersonRow extends StatelessWidget {
  const PeopleTagPersonRow({
    required this.id,
    required this.profile,
    this.trailing,
    this.showInheritedMarker = false,
    this.inheritedSemanticsLabel,
    super.key,
  });

  final String id;

  /// Null while the profile is still loading.
  final Profile? profile;
  final Widget? trailing;
  final bool showInheritedMarker;
  final String? inheritedSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile ?? Profile(id: id);
    final tt = context.tt;
    final inheritedLabel = inheritedSemanticsLabel;
    final tile = ListTile(
      key: Key('people-tag-person-$id'),
      leading: TenturaAvatar(profile: profile),
      title: Row(
        children: [
          Expanded(
            child: Text(this.profile == null ? id : profile.shownName),
          ),
          if (showInheritedMarker) ...[
            SizedBox(width: tt.iconTextGap),
            InheritedTagMarker(color: tt.text),
          ],
        ],
      ),
      trailing: trailing,
    );
    if (showInheritedMarker && inheritedLabel != null) {
      return Semantics(
        label:
            '${this.profile == null ? id : profile.shownName}. $inheritedLabel',
        child: tile,
      );
    }
    return tile;
  }
}
