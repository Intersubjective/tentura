import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

import 'add_to_tag_sheet.dart';
import 'person_auto_tag_name.dart';
import 'person_own_tag_chip.dart';
import 'people_tag_profiles.dart';

/// The viewer's private tags on one person: own tags with ×, the automatic
/// ones without, and "+ Tag" to edit the person's membership.
class PersonTagsBlock extends StatefulWidget {
  const PersonTagsBlock({required this.personId, this.trust, super.key});

  final String personId;

  /// Live explicit trust from the selected profile, including pending writes.
  /// Other automatic tags still come from the person's server snapshot.
  final ({bool viewerTrusts, bool trustsViewer})? trust;

  @override
  State<PersonTagsBlock> createState() => _PersonTagsBlockState();
}

class _PersonTagsBlockState extends State<PersonTagsBlock> {
  final _peopleTags = GetIt.I<PeopleTagsCase>();
  final _profiles = PeopleTagProfiles();

  late Future<List<PersonAutoTagOf>> _auto;

  @override
  void initState() {
    super.initState();
    unawaited(_peopleTags.ensureLoaded().catchError((Object _) {}));
    _auto = _loadAuto();
  }

  @override
  void didUpdateWidget(PersonTagsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) _auto = _loadAuto();
  }

  Future<List<PersonAutoTagOf>> _loadAuto() => _peopleTags
      .autoTagsOf(widget.personId)
      .catchError((Object _) => const <PersonAutoTagOf>[]);

  Future<void> _remove(PersonTag tag) async {
    final l10n = L10n.of(context)!;
    final inviterId = _peopleTags.inheritedFrom(tag.id, widget.personId);
    try {
      await _peopleTags.removeFromTag(
        personId: widget.personId,
        tagId: tag.id,
      );
      if (!mounted) return;
      showUndoSnackBar(
        context,
        text: l10n.peopleTagsRemovedFromPersonOnPeer(tag.name),
        onUndo: () => unawaited(
          _undoRemove(tag: tag, inviterId: inviterId),
        ),
      );
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

  Future<void> _undoRemove({
    required PersonTag tag,
    required String? inviterId,
  }) async {
    try {
      await _peopleTags.addToTag(
        personId: widget.personId,
        tagId: tag.id,
      );
      if (inviterId != null) {
        _peopleTags.restoreInheritedMarker(
          tagId: tag.id,
          personId: widget.personId,
          inviterId: inviterId,
        );
      }
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

  Future<void> _keep(String tagId) async {
    try {
      await _peopleTags.keepInherited(
        personId: widget.personId,
        tagId: tagId,
      );
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

  Future<void> _ensureInviterProfiles(Set<String> inviterIds) async {
    if (inviterIds.isEmpty) return;
    final arrived = await _profiles.ensure(inviterIds);
    if (arrived && mounted) setState(() {});
  }

  /// One chip per automatic tag kind: the source may emit a row per shared
  /// Request or event, the first row of a kind wins.
  static List<PersonAutoTagOf> _onePerKind(List<PersonAutoTagOf> tags) {
    final seen = <int>{};
    return [
      for (final tag in tags)
        if (seen.add(tag.kind)) tag,
    ];
  }

  List<PersonAutoTagOf> _currentAutoTags(List<PersonAutoTagOf> tags) {
    final trust = widget.trust;
    if (trust == null) return _onePerKind(tags);
    const trustKinds = {
      PersonAutoTagKind.mutualContact,
      PersonAutoTagKind.iTrust,
      PersonAutoTagKind.trustsMe,
    };
    return _onePerKind([
      for (final kind in [
        if (trust.viewerTrusts && trust.trustsViewer)
          PersonAutoTagKind.mutualContact,
        if (trust.viewerTrusts) PersonAutoTagKind.iTrust,
        if (trust.trustsViewer) PersonAutoTagKind.trustsMe,
      ])
        PersonAutoTagOf(kind: kind.smallintValue, n: 1, direction: 0),
      for (final tag in tags)
        if (!trustKinds.any((kind) => kind.smallintValue == tag.kind)) tag,
    ]);
  }

  static String _autoName(L10n l10n, PersonAutoTagOf tag) {
    final name = personAutoTagName(l10n, tag.kind);
    return tag.n > 1 ? '$name · ${tag.n}' : name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final tt = context.tt;
    final spacing = tt.iconTextGap * 2;
    final runSpacing = tt.tightGap * 2;
    final maxChipWidth =
        MediaQuery.sizeOf(context).width - tt.screenHPadding * 2;
    return StreamBuilder<void>(
      stream: _peopleTags.changes,
      builder: (context, _) {
        final own = _peopleTags.tagsOfPerson(widget.personId);
        final inviterIds = {
          for (final tag in _peopleTags.tags)
            if (own.contains(tag.id) &&
                _peopleTags.isInheritedMember(tag.id, widget.personId))
              _peopleTags.inheritedFrom(tag.id, widget.personId),
        }.whereType<String>().toSet();
        unawaited(_ensureInviterProfiles(inviterIds));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.peopleTagsYourTags, style: textTheme.labelLarge),
            SizedBox(height: runSpacing),
            Wrap(
              spacing: spacing,
              runSpacing: runSpacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in _peopleTags.tags)
                  if (own.contains(tag.id))
                    PersonOwnTagChip(
                      tag: tag,
                      personId: widget.personId,
                      profiles: _profiles,
                      maxWidth: maxChipWidth,
                      onKeep: () => unawaited(_keep(tag.id)),
                      onRemove: () => unawaited(_remove(tag)),
                    ),
                TextButton(
                  onPressed: () => unawaited(
                    showAddToTagSheet(context, personId: widget.personId),
                  ),
                  child: Text(l10n.constellationTagRowAdd),
                ),
              ],
            ),
            FutureBuilder<List<PersonAutoTagOf>>(
              future: _auto,
              builder: (context, snapshot) {
                final auto = _currentAutoTags(
                  snapshot.data ?? const <PersonAutoTagOf>[],
                );
                if (auto.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: tt.rowGap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.peopleTagsAutomatic,
                        style: textTheme.labelLarge,
                      ),
                      SizedBox(height: runSpacing),
                      Wrap(
                        spacing: spacing,
                        runSpacing: runSpacing,
                        children: [
                          for (final tag in auto)
                            AutoTagChip(name: _autoName(l10n, tag)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: tt.rowGap),
            Text(l10n.peopleTagsOnlyYouSee, style: textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
