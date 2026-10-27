import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'tag_editor_dialog.dart';

/// Lets the viewer tick the own tags [personId] belongs to. Nothing is sent
/// while the sheet is open; closing it (barrier, back, drag) sends the whole
/// change as one batch.
Future<void> showAddToTagSheet(
  BuildContext context, {
  required String personId,
}) => showAddPeopleToTagSheet(context, personIds: [personId]);

/// [showAddToTagSheet] for several people at once: a tag is ticked when every
/// one of [personIds] is in it, and the change closing the sheet makes (a tag
/// ticked or unticked) goes to all of them in one batch.
Future<void> showAddPeopleToTagSheet(
  BuildContext context, {
  required Iterable<String> personIds,
}) async {
  final people = personIds.toSet();
  final peopleTags = GetIt.I<PeopleTagsCase>();
  try {
    await peopleTags.ensureLoaded();
  } catch (e, s) {
    if (context.mounted) {
      showSnackBar(
        context,
        isError: true,
        text: e.toString(),
        error: e,
        stackTrace: s,
      );
    }
    return;
  }
  if (!context.mounted) return;
  final initial = {
    for (final tag in peopleTags.tags)
      if (people.every((id) => peopleTags.tagsOfPerson(id).contains(tag.id)))
        tag.id,
  };
  final checked = {...initial};
  await showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => _AddToTagSheet(
      peopleTags: peopleTags,
      checked: checked,
    ),
  );
  final ops = [
    for (final id in checked.difference(initial))
      for (final personId in people)
        if (!peopleTags.tagsOfPerson(personId).contains(id))
          PersonTagMemberOp(tagId: id, personId: personId, add: true),
    for (final id in initial.difference(checked))
      for (final personId in people)
        PersonTagMemberOp(tagId: id, personId: personId, add: false),
  ];
  if (ops.isEmpty) return;
  try {
    await peopleTags.applyMembership(ops);
  } catch (e, s) {
    if (context.mounted) {
      showSnackBar(
        context,
        isError: true,
        text: e.toString(),
        error: e,
        stackTrace: s,
      );
    }
  }
}

class _AddToTagSheet extends StatefulWidget {
  const _AddToTagSheet({required this.peopleTags, required this.checked});

  final PeopleTagsCase peopleTags;

  /// Ids of the ticked tags; edited in place so the opener sees the result.
  final Set<String> checked;

  @override
  State<_AddToTagSheet> createState() => _AddToTagSheetState();
}

class _AddToTagSheetState extends State<_AddToTagSheet> {
  Future<void> _newTag() async {
    final tag = await showTagEditorDialog(
      context,
      onSave: (name, glyph, color) =>
          widget.peopleTags.createTag(name: name, glyph: glyph, color: color),
    );
    if (tag == null || !mounted) return;
    setState(() => widget.checked.add(tag.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return StreamBuilder<void>(
      stream: widget.peopleTags.changes,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: Text(
              l10n.peopleTagsAddToTag,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final tag in widget.peopleTags.tags)
                  CheckboxListTile(
                    value: widget.checked.contains(tag.id),
                    onChanged: (on) => setState(() {
                      if (on ?? false) {
                        widget.checked.add(tag.id);
                      } else {
                        widget.checked.remove(tag.id);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        TagGlyph(glyph: tag.glyph, colorIndex: tag.color),
                        SizedBox(width: tt.rowGap),
                        Expanded(child: Text(tag.name)),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.peopleTagsNewTag),
                  onTap: _newTag,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              tt.screenHPadding,
              tt.rowGap,
              tt.screenHPadding,
              tt.sectionGap,
            ),
            child: Text(
              l10n.peopleTagsOnlyYouSee,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
