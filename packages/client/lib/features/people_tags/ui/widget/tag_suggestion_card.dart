import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// "Tag them?": offers to put [personIds] into one of the own tags. Shown
/// once per [event] and only when the server allows suggestions; Not now and
/// Add record the outcome and remove the card.
class TagSuggestionCard extends StatefulWidget {
  const TagSuggestionCard({
    required this.event,
    required this.personIds,
    required this.names,
    super.key,
  });

  final PeopleTagSuggestionEvent event;
  final List<String> personIds;
  final String names;

  @override
  State<TagSuggestionCard> createState() => _TagSuggestionCardState();
}

class _TagSuggestionCardState extends State<TagSuggestionCard> {
  final _peopleTags = GetIt.I<PeopleTagsCase>();
  final _suggestions = GetIt.I<PeopleTagSuggestionCase>();

  bool _visible = false;
  String? _pickedTagId;

  @override
  void initState() {
    super.initState();
    unawaited(_peopleTags.ensureLoaded().catchError((Object _) {}));
    unawaited(_check());
  }

  @override
  void didUpdateWidget(TagSuggestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event == widget.event) return;
    _visible = false;
    _pickedTagId = null;
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final show = await _suggestions.shouldShow(widget.event);
      if (show && mounted) setState(() => _visible = true);
    } catch (_) {
      // A failed state read just means no card.
    }
  }

  Future<void> _notNow() async {
    setState(() => _visible = false);
    try {
      await _suggestions.notNow(widget.event);
    } catch (_) {}
  }

  Future<void> _disable() async {
    setState(() => _visible = false);
    try {
      await _suggestions.disable();
    } catch (_) {}
  }

  Future<void> _add() async {
    final tagId = _pickedTagId;
    if (tagId == null) return;
    try {
      await _peopleTags.applyMembership([
        for (final id in widget.personIds)
          PersonTagMemberOp(tagId: tagId, personId: id, add: true),
      ]);
      await _suggestions.accepted(widget.event);
      if (mounted) setState(() => _visible = false);
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

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Card(
      key: const ValueKey('tag-suggestion-card'),
      child: Padding(
        padding: EdgeInsets.all(tt.screenHPadding),
        child: StreamBuilder<void>(
          stream: _peopleTags.changes,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.peopleTagsSuggestionTitle(widget.names),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              Wrap(
                spacing: tt.rowGap,
                children: [
                  for (final tag in _peopleTags.tags)
                    ChoiceChip(
                      label: Text(tag.name),
                      selected: _pickedTagId == tag.id,
                      onSelected: (_) => setState(() => _pickedTagId = tag.id),
                    ),
                ],
              ),
              SizedBox(height: tt.rowGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('tag-suggestion-not-now'),
                    onPressed: _notNow,
                    child: Text(l10n.peopleTagsSuggestionNotNow),
                  ),
                  FilledButton(
                    key: const ValueKey('tag-suggestion-add'),
                    onPressed: _pickedTagId == null ? null : _add,
                    child: Text(l10n.peopleTagsSuggestionAdd),
                  ),
                  PopupMenuButton<void>(
                    key: const ValueKey('tag-suggestion-menu'),
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    itemBuilder: (_) => [
                      PopupMenuItem<void>(
                        key: const ValueKey('tag-suggestion-dont-suggest'),
                        onTap: () => unawaited(_disable()),
                        child: Text(l10n.peopleTagsDontSuggest),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
