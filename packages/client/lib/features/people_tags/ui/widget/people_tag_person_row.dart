import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

/// One person of a tag; [trailing] is the × of an own tag.
class PeopleTagPersonRow extends StatelessWidget {
  const PeopleTagPersonRow({
    required this.id,
    required this.profile,
    this.trailing,
    super.key,
  });

  final String id;

  /// Null while the profile is still loading.
  final Profile? profile;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile ?? Profile(id: id);
    return ListTile(
      key: Key('people-tag-person-$id'),
      leading: TenturaAvatar(profile: profile),
      title: Text(this.profile == null ? id : profile.shownName),
      trailing: trailing,
    );
  }
}
