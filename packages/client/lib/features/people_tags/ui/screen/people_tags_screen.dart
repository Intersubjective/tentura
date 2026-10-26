import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';

import '../widget/person_auto_tag_name.dart';

/// The viewer's own tags (reorder, delete with Undo) and the switches that
/// put the automatic tags into the Field filters.
@RoutePage()
class PeopleTagsScreen extends StatefulWidget {
  const PeopleTagsScreen({super.key});

  @override
  State<PeopleTagsScreen> createState() => _PeopleTagsScreenState();
}

class _PeopleTagsScreenState extends State<PeopleTagsScreen> {
  final _peopleTags = GetIt.I<PeopleTagsCase>();

  @override
  void initState() {
    super.initState();
    unawaited(
      _run(() async {
        await _peopleTags.load();
        await _peopleTags.loadAutoTags();
        await _peopleTags.loadSuggestionState();
      }),
    );
  }

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

  Future<void> _setSuggestions({required bool on}) => _run(() async {
    final suggestions = GetIt.I<PeopleTagSuggestionCase>();
    await (on ? suggestions.enable() : suggestions.disable());
    await _peopleTags.loadSuggestionState();
  });

  Future<void> _delete(String id) => _run(() async {
    final snapshot = await _peopleTags.deleteTag(id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      text: L10n.of(context)!.peopleTagsDeleted,
      onUndo: () => unawaited(_run(() => _peopleTags.restoreTag(snapshot))),
    );
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        title: Text(l10n.peopleTagsScreenTitle),
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: StreamBuilder<void>(
            stream: _peopleTags.changes,
            builder: (context, _) {
              final tags = _peopleTags.tags;
              final auto = _peopleTags.autoTags;
              return ListView(
                padding: EdgeInsets.all(tt.screenHPadding),
                children: [
                  TenturaSectionHeader(label: l10n.peopleTagsYourTags),
                  for (var i = 0; i < tags.length; i++)
                    _TagRow(
                      tag: tags[i],
                      canMoveUp: i > 0,
                      canMoveDown: i < tags.length - 1,
                      onMove: (ord) => unawaited(
                        _run(
                          () => _peopleTags.moveTag(id: tags[i].id, ord: ord),
                        ),
                      ),
                      onDelete: () => unawaited(_delete(tags[i].id)),
                      position: i + 1,
                    ),
                  if (auto.isNotEmpty) ...[
                    SizedBox(height: tt.sectionGap),
                    TenturaSectionHeader(label: l10n.peopleTagsAutomatic),
                    for (final a in auto)
                      ListTile(
                        onTap: () => unawaited(
                          context.router.push(PeopleAutoTagRoute(kind: a.kind)),
                        ),
                        title: Text(personAutoTagName(l10n, a.kind)),
                        subtitle: Text(l10n.peopleTagsShowInFilters),
                        leading: Text('${a.count}'),
                        trailing: Switch(
                          key: Key('people-tags-auto-switch-${a.kind}'),
                          value: a.showInFilters,
                          onChanged: (v) => unawaited(
                            _run(
                              () => _peopleTags.setAutoTagShownInFilters(
                                kind: a.kind,
                                show: v,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  SizedBox(height: tt.sectionGap),
                  ListTile(
                    title: Text(l10n.peopleTagsSuggestEnable),
                    trailing: Switch(
                      key: const Key('people-tags-suggestions-switch'),
                      value: _peopleTags.suggestionsEnabled,
                      onChanged: (v) => unawaited(_setSuggestions(on: v)),
                    ),
                  ),
                  SizedBox(height: tt.rowGap),
                  Text(
                    l10n.peopleTagsOnlyYouSee,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.position,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMove,
    required this.onDelete,
  });

  final PersonTag tag;

  /// 1-based place of the tag in the list.
  final int position;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return ListTile(
      onTap: () =>
          unawaited(context.router.push(PeopleTagRoute(tagId: tag.id))),
      leading: TagGlyph(glyph: tag.glyph, colorIndex: tag.color),
      title: Text(tag.name),
      subtitle: tag.countOffField > 0
          ? Text(l10n.peopleTagsOffField(tag.countOffField))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${tag.count}'),
          PopupMenuButton<void>(
            key: Key('people-tags-row-menu-${tag.id}'),
            popUpAnimationStyle: AnimationStyle.noAnimation,
            itemBuilder: (_) => [
              if (canMoveUp)
                PopupMenuItem<void>(
                  key: Key('people-tags-move-up-${tag.id}'),
                  onTap: () => onMove(position - 1),
                  child: Text(l10n.peopleTagsMoveUp),
                ),
              if (canMoveDown)
                PopupMenuItem<void>(
                  key: Key('people-tags-move-down-${tag.id}'),
                  onTap: () => onMove(position + 1),
                  child: Text(l10n.peopleTagsMoveDown),
                ),
              PopupMenuItem<void>(
                key: Key('people-tags-delete-${tag.id}'),
                onTap: onDelete,
                child: Text(l10n.peopleTagsDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
