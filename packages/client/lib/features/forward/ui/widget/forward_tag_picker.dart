import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_auto_tag_name.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/forward_cubit.dart';

/// The viewer's own and automatic tags as chips above the recipient list:
/// a tap picks the tag's eligible people through [ForwardCubit.toggleTag].
/// Also the individual-forward note and the outside-the-tag hint.
class ForwardTagPicker extends StatefulWidget {
  const ForwardTagPicker({
    required this.state,
    required this.onToggle,
    this.activeTagMembers,
    this.onToggleTag,
    super.key,
  });

  final ForwardState state;

  /// Row toggle of the hint people; the picker's own toggle routing.
  final ValueChanged<String> onToggle;

  /// Hosts without a [ForwardCubit] (the graph composer) say which tags are
  /// picked, with their members, and receive the taps; both default to the
  /// cubit's.
  final Map<String, Set<String>>? activeTagMembers;

  final void Function(String tagId, Iterable<String> memberIds)? onToggleTag;

  @override
  State<ForwardTagPicker> createState() => _ForwardTagPickerState();
}

class _ForwardTagPickerState extends State<ForwardTagPicker> {
  final PeopleTagsCase? _peopleTags = GetIt.I.isRegistered<PeopleTagsCase>()
      ? GetIt.I<PeopleTagsCase>()
      : null;
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    final peopleTags = _peopleTags;
    if (peopleTags == null) return;
    _subscription = peopleTags.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(peopleTags.loadAutoTags().catchError((_) {}));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Set<String> get _active =>
      (widget.activeTagMembers ?? widget.state.addedByTag).keys.toSet();

  void _toggleTag(String id, Iterable<String> members) {
    final onToggleTag = widget.onToggleTag;
    if (onToggleTag != null) return onToggleTag(id, members);
    context.read<ForwardCubit>().toggleTag(id, members);
  }

  Future<void> _toggleAuto(int kind) async {
    final id = _autoId(kind);
    if (_active.contains(id)) {
      _toggleTag(id, const []);
      return;
    }
    final members = await _peopleTags!.autoTagMembers(kind);
    if (mounted) _toggleTag(id, members);
  }

  static String _autoId(int kind) => 'auto-$kind';

  @override
  Widget build(BuildContext context) {
    final peopleTags = _peopleTags;
    if (peopleTags == null) return const SizedBox.shrink();
    final autoTags = [
      for (final t in peopleTags.autoTags)
        if (t.showInFilters) t,
    ];
    if (peopleTags.tags.isEmpty && autoTags.isEmpty) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final state = widget.state;
    final active = _active;
    final outside = active.isEmpty
        ? const <ForwardCandidate>[]
        : state.outsideTagSuggestions({
            for (final ids
                in (widget.activeTagMembers ?? state.tagMembers).values)
              ...ids,
          });

    Widget chip({
      required Key key,
      required bool isActive,
      required Widget child,
      required VoidCallback onTap,
    }) => Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TenturaRadii.avatar),
            border: isActive ? Border.all(color: tt.info, width: 2) : null,
          ),
          child: child,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.rowGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: tt.rowGap,
            runSpacing: tt.rowGap,
            children: [
              for (final PersonTag tag in peopleTags.tags)
                chip(
                  key: ValueKey('forward-tag-chip-${tag.id}'),
                  isActive: active.contains(tag.id),
                  onTap: () =>
                      _toggleTag(tag.id, peopleTags.peopleInTag(tag.id)),
                  child: PersonTagChip(
                    glyph: tag.glyph,
                    name: tag.name,
                    colorIndex: tag.color,
                  ),
                ),
              for (final PersonAutoTag tag in autoTags)
                chip(
                  key: ValueKey('forward-tag-chip-auto-${tag.kind}'),
                  isActive: active.contains(_autoId(tag.kind)),
                  onTap: () => unawaited(_toggleAuto(tag.kind)),
                  child: AutoTagChip(name: personAutoTagName(l10n, tag.kind)),
                ),
            ],
          ),
          SizedBox(height: tt.rowGap),
          Column(
            key: const ValueKey('forward-tag-note'),
            children: [
              Text(
                l10n.peopleTagsForwardNote,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ],
          ),
          if (outside.isNotEmpty) ...[
            SizedBox(height: tt.rowGap),
            Column(
              key: const ValueKey('forward-tag-outside-hint'),
              children: [
                Text(
                  l10n.peopleTagsForwardOutsideTag,
                  style: TenturaText.labelSmall(tt.textMuted),
                ),
              ],
            ),
            for (final c in outside)
              InkWell(
                key: ValueKey('forward-tag-outside-${c.id}'),
                onTap: () => widget.onToggle(c.id),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.profile.shownName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.body(tt.text),
                        ),
                      ),
                      if (state.selectedIds.contains(c.id))
                        Icon(Icons.check, size: tt.iconSize, color: tt.info),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
