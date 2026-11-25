import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom.dart';
import 'package:tentura/features/phantoms/domain/exception.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_invite_presentation.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

class PeopleWithoutAccounts extends StatelessWidget {
  const PeopleWithoutAccounts({
    required this.people,
    required this.onInviteChanged,
    super.key,
  });

  final List<Phantom> people;
  final Future<void> Function() onInviteChanged;

  @override
  Widget build(BuildContext context) {
    final tags = GetIt.I<PeopleTagsCase>();
    return StreamBuilder<void>(
      stream: tags.changes,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(top: context.tt.sectionGap),
            child: Semantics(
              header: true,
              child: Text(
                L10n.of(context)!.peopleWithoutAccounts,
                style: TenturaText.titleSmall(context.tt.textMuted),
              ),
            ),
          ),
          for (final person in people)
            _PersonRow(
              key: ValueKey(person.id),
              person: person,
              tags: [
                for (final tag in tags.tags)
                  if (person.ownTagIds.contains(tag.id)) tag,
              ],
              onInviteChanged: onInviteChanged,
            ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatefulWidget {
  const _PersonRow({
    required this.person,
    required this.tags,
    required this.onInviteChanged,
    super.key,
  });

  final Phantom person;
  final List<PersonTag> tags;
  final Future<void> Function() onInviteChanged;

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    final person = widget.person;
    final onInviteChanged = widget.onInviteChanged;
    setState(() => _copying = true);
    try {
      await copyPhantomInviteLink(context, id: person.id);
      await onInviteChanged();
    } on Exception catch (error, trace) {
      if (!mounted) return;
      final l10n = L10n.of(context)!;
      final joining = error is PhantomJoiningException;
      showSnackBar(
        context,
        text: joining
            ? l10n.personPanelJoining(person.displayName)
            : l10n.errorGenericAction,
        isError: !joining,
        error: joining ? null : error,
        stackTrace: trace,
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final person = widget.person;
    final compact = context.windowClass == WindowClass.compact;
    final copy = TextButton(
      onPressed: _copying ? null : () => unawaited(_copy()),
      child: Text(l10n.personCopyLink),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RelativeTimestampTicker(
                      builder: (_) => TenturaStatusText(
                        phantomInviteAge(
                              person,
                              RelativeTimestampTicker.now(),
                              l10n,
                            ) ??
                            l10n.personInviteNotSent,
                        maxLines: null,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) copy,
            ],
          ),
          if (widget.tags.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: tt.tightGap,
                runSpacing: tt.tightGap,
                children: [
                  for (final tag in widget.tags)
                    PersonTagChip(
                      glyph: tag.glyph,
                      name: tag.name,
                      colorIndex: tag.color,
                      maxWidth: constraints.maxWidth,
                    ),
                ],
              ),
            ),
          if (compact) copy,
        ],
      ),
    );
  }
}
