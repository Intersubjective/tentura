import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../widget/add_people_sheet.dart';
import '../widget/people_tag_person_row.dart';
import '../widget/people_tag_profiles.dart';
import '../widget/tag_editor_dialog.dart';

/// One own tag: its people with ×, the editor, and Add people.
@RoutePage()
class PeopleTagScreen extends StatefulWidget {
  const PeopleTagScreen({
    @PathParam('tagId') this.tagId = '',
    super.key,
  });

  final String tagId;

  @override
  State<PeopleTagScreen> createState() => _PeopleTagScreenState();
}

class _PeopleTagScreenState extends State<PeopleTagScreen> {
  final _peopleTags = GetIt.I<PeopleTagsCase>();
  final _profiles = PeopleTagProfiles();

  late final StreamSubscription<void> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _peopleTags.changes.listen((_) => _loadProfiles());
    unawaited(_run(_peopleTags.load));
    _loadProfiles();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  void _loadProfiles() => unawaited(
    _run(() async {
      final arrived = await _profiles.ensure(
        _peopleTags.peopleInTag(widget.tagId),
      );
      if (arrived && mounted) setState(() {});
    }),
  );

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, s) {
      if (mounted) {
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

  PersonTag? get _tag {
    for (final t in _peopleTags.tags) {
      if (t.id == widget.tagId) return t;
    }
    return null;
  }

  Future<void> _edit(PersonTag tag) => showTagEditorDialog(
    context,
    initial: tag,
    onSave: (name, glyph, color) => _peopleTags.updateTag(
      id: tag.id,
      name: name,
      glyph: glyph,
      color: color,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return StreamBuilder<void>(
      stream: _peopleTags.changes,
      builder: (context, _) {
        final tag = _tag;
        final people = _peopleTags.peopleInTag(widget.tagId).toList()
          ..sort((a, b) => _label(a).compareTo(_label(b)));
        return Scaffold(
          appBar: TenturaTopBar.of(
            context,
            title: Text(tag?.name ?? ''),
            actions: [
              if (tag != null)
                IconButton(
                  key: const Key('people-tag-edit'),
                  tooltip: l10n.peopleTagsEditTitle,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => unawaited(_edit(tag)),
                ),
            ],
          ),
          body: SafeArea(
            child: TenturaContentColumn(
              child: ListView(
                padding: EdgeInsets.all(tt.screenHPadding),
                children: [
                  Row(
                    children: [
                      if (tag != null)
                        TagGlyph(glyph: tag.glyph, colorIndex: tag.color),
                      SizedBox(width: tt.rowGap),
                      Text(
                        '${people.length}',
                        key: const Key('people-tag-count'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        key: const Key('people-tag-add-people'),
                        onPressed: tag == null
                            ? null
                            : () => unawaited(
                                _run(
                                  () => showAddPeopleSheet(
                                    context,
                                    tagId: widget.tagId,
                                  ),
                                ),
                              ),
                        child: Text(l10n.peopleTagsAddPeople),
                      ),
                    ],
                  ),
                  SizedBox(height: tt.rowGap),
                  for (final id in people)
                    PeopleTagPersonRow(
                      id: id,
                      profile: _profiles.of(id),
                      trailing: IconButton(
                        key: Key('people-tag-person-remove-$id'),
                        tooltip: l10n.peopleTagsRemovePerson(_label(id)),
                        icon: const Icon(Icons.close),
                        onPressed: () => unawaited(
                          _run(
                            () => _peopleTags.removeFromTag(
                              personId: id,
                              tagId: widget.tagId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(height: tt.rowGap),
                  Text(
                    l10n.peopleTagsOnlyYouSee,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _label(String id) => _profiles.of(id)?.shownName ?? id;
}
