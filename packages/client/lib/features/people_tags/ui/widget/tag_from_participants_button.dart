import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'tag_editor_dialog.dart';

/// Creates an own tag filled with the other members of a Request. Offered
/// only to a member of a Request, never on a Post.
class TagFromParticipantsButton extends StatelessWidget {
  const TagFromParticipantsButton({
    required this.beaconId,
    required this.isRequest,
    required this.viewerIsMember,
    super.key,
  });

  final String beaconId;
  final bool isRequest;
  final bool viewerIsMember;

  @override
  Widget build(BuildContext context) {
    final peopleTags = GetIt.I<PeopleTagsCase>();
    if (!peopleTags.canTagFromParticipants(
      viewerIsMember: viewerIsMember,
      isRequest: isRequest,
    )) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: const ValueKey('tag-from-participants'),
      icon: const Icon(Icons.group_add_outlined),
      label: Text(L10n.of(context)!.peopleTagsFromParticipants),
      onPressed: () => unawaited(
        showTagEditorDialog(
          context,
          onSave: (name, glyph, color) => peopleTags.createTag(
            name: name,
            glyph: glyph,
            color: color,
            fromBeaconId: beaconId,
          ),
        ),
      ),
    );
  }
}
