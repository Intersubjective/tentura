import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../domain/entity/person_note.dart';
import '../../domain/entity/phantom.dart';
import '../../domain/exception.dart';
import '../../domain/port/phantom_repository_port.dart';
import 'phantom_invite_presentation.dart';
import 'person_notes_block.dart';

class PhantomContextPanel extends StatefulWidget {
  const PhantomContextPanel({
    required this.person,
    required this.tags,
    required this.nowUtc,
    required this.linkCandidates,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final Phantom person;
  final List<PersonTag> tags;
  final DateTime nowUtc;
  final List<({String id, String name})> Function() linkCandidates;
  final Future<void> Function() onChanged;
  final VoidCallback onClose;

  @override
  State<PhantomContextPanel> createState() => _PhantomContextPanelState();
}

class _PhantomContextPanelState extends State<PhantomContextPanel> {
  bool _busy = false;

  PhantomRepositoryPort get _repository => GetIt.I<PhantomRepositoryPort>();

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    final onChanged = widget.onChanged;
    setState(() => _busy = true);
    try {
      if (await action()) await onChanged();
    } on Exception catch (error, trace) {
      if (mounted) {
        final l10n = L10n.of(context)!;
        final joining = error is PhantomJoiningException;
        showSnackBar(
          context,
          text: joining
              ? l10n.personPanelJoining(widget.person.displayName)
              : l10n.errorGenericAction,
          // The joining status includes a private name. Error bars log copy.
          isError: !joining,
          isFloating: joining,
          error: joining ? null : error,
          stackTrace: trace,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _copy({required bool rotate}) async {
    await copyPhantomInviteLink(context, id: widget.person.id, rotate: rotate);
    return true;
  }

  Future<bool> _link() async {
    final userId = await pickPersonToLink(context, widget.linkCandidates());
    if (!mounted || userId == null) return false;
    await _repository.link(phantomId: widget.person.id, userId: userId);
    return true;
  }

  Future<bool> _remove() async {
    final l10n = L10n.of(context)!;
    final person = widget.person;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.personPanelRemoveTitle,
      content: l10n.personPanelRemoveBody(person.displayName),
      cancelLabel: l10n.buttonCancel,
      confirmLabel: l10n.buttonRemove,
    );
    if (!mounted || confirmed != true) return false;
    await _repository.delete(id: person.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final person = widget.person;
    final age = phantomInviteAge(person, widget.nowUtc, l10n);
    final status = age == null
        ? l10n.constellationPhantomStatus
        : '${l10n.constellationPhantomStatus} · $age';

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: SingleChildScrollView(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    person.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.buttonClose,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TenturaStatusText(status, maxLines: null),
            if (widget.tags.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              Wrap(
                spacing: tt.tightGap,
                runSpacing: tt.tightGap,
                children: [
                  for (final tag in widget.tags)
                    PersonTagChip(
                      glyph: tag.glyph,
                      name: tag.name,
                      colorIndex: tag.color,
                    ),
                ],
              ),
            ],
            PersonNotesBlock(subject: PhantomNoteSubject(person.id)),
            SizedBox(height: tt.sectionGap),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(() => _copy(rotate: false)),
              child: Text(l10n.personCreateCopyInvite),
            ),
            OutlinedButton(
              onPressed: _busy || person.inviteState != PhantomInviteState.live
                  ? null
                  : () => _run(() => _copy(rotate: true)),
              child: Text(l10n.personPanelNewLink),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_link),
              child: Text(l10n.personPanelLinkExisting),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_remove),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l10n.personPanelRemove),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> pickPersonToLink(
  BuildContext context,
  List<({String id, String name})> people,
) {
  final l10n = L10n.of(context)!;
  return showTenturaAdaptiveSheet<String>(
    context: context,
    builder: (context) {
      final tt = context.tt;
      return Padding(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.personPanelPickExisting,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: tt.rowGap),
            if (people.isEmpty)
              Text(l10n.personPanelNoPeople)
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return ListTile(
                      title: Text(person.name),
                      onTap: () => Navigator.of(context).pop(person.id),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
