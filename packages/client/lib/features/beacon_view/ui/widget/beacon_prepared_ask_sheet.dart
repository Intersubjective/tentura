import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

Future<void> showPreparedAskEditorSheet(
  BuildContext context, {
  required String beaconId,
  required VoidCallback onSaved,
  CoordinationItem? existing,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PreparedAskEditorSheetBody(
      beaconId: beaconId,
      coordinationCase: coordinationCase,
      existing: existing,
      l10n: l10n,
    ),
  );
  if (ok == true && context.mounted) {
    onSaved();
  }
}

class _PreparedAskEditorSheetBody extends StatefulWidget {
  const _PreparedAskEditorSheetBody({
    required this.beaconId,
    required this.coordinationCase,
    required this.existing,
    required this.l10n,
  });

  final String beaconId;
  final CoordinationItemCase coordinationCase;
  final CoordinationItem? existing;
  final L10n l10n;

  @override
  State<_PreparedAskEditorSheetBody> createState() =>
      _PreparedAskEditorSheetBodyState();
}

class _PreparedAskEditorSheetBodyState extends State<_PreparedAskEditorSheetBody> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _bodyController = TextEditingController(text: existing?.body ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit =
        _titleController.text.trim().isNotEmpty && !_submitting;
    final l10n = widget.l10n;
    final existing = widget.existing;
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingSmall,
        right: kSpacingSmall,
        top: kSpacingMedium,
        bottom: bottom + kSpacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null
                ? l10n.beaconPreparedAskEditorTitleNew
                : l10n.beaconPreparedAskEditorTitleEdit,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.labelTitle,
            ),
            textInputAction: TextInputAction.next,
            enabled: !_submitting,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _bodyController,
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              hintText: l10n.beaconRoomSelfAskBodyHintOptional,
            ),
            enabled: !_submitting,
          ),
          const SizedBox(height: kSpacingMedium),
          FilledButton(
            onPressed: !canSubmit
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      if (existing == null) {
                        await widget.coordinationCase.createDraftAsk(
                          beaconId: widget.beaconId,
                          title: _titleController.text.trim(),
                          body: _bodyController.text.trim(),
                        );
                      } else {
                        await widget.coordinationCase.updateDraftAsk(
                          itemId: existing.id,
                          title: _titleController.text.trim(),
                          body: _bodyController.text.trim(),
                          omitTargetPersonId: true,
                        );
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    } on Object catch (_) {
                      if (context.mounted) {
                        setState(() => _submitting = false);
                      }
                    }
                  },
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
  }
}

Future<void> showPreparedAskPublishSheet(
  BuildContext context, {
  required CoordinationItem draft,
  required List<BeaconParticipant> participants,
  required String beaconAuthorId,
  required VoidCallback onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final viewerId = GetIt.I<ProfileCubit>().state.profile.id;

  final candidateIds = <String>{beaconAuthorId};
  for (final p in participants) {
    candidateIds.add(p.userId);
  }
  final sortedIds = candidateIds.toList()..sort();

  var selectedId = draft.targetPersonId;
  if (selectedId != null && !candidateIds.contains(selectedId)) {
    selectedId = null;
  }

  var submitting = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          final screenH = MediaQuery.sizeOf(ctx).height;
          final listMaxCandidate = screenH * 0.45;
          final listMaxHeight =
              listMaxCandidate < 360 ? listMaxCandidate : 360.0;
          return Padding(
            padding: EdgeInsets.only(
              left: kSpacingSmall,
              right: kSpacingSmall,
              top: kSpacingMedium,
              bottom: bottom + kSpacingMedium,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.beaconPreparedAskPublishSheetTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpacingSmall),
                Text(
                  draft.title,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: kSpacingSmall),
                SizedBox(
                  height: listMaxHeight,
                  child: ListView(
                    children: [
                      for (final userId in sortedIds)
                        ListTile(
                          selected: selectedId == userId,
                          enabled: !submitting,
                          onTap: submitting
                              ? null
                              : () => setState(() => selectedId = userId),
                          title: Text(_labelForCandidate(
                            userId: userId,
                            participants: participants,
                            viewerId: viewerId,
                            l10n: l10n,
                          )),
                          subtitle: Text(
                            userId == viewerId ? l10n.labelMe : userId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            selectedId == userId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: kSpacingMedium),
                FilledButton(
                  onPressed: submitting || selectedId == null
                      ? null
                      : () async {
                          setState(() => submitting = true);
                          try {
                            await coordinationCase.publishDraftAsk(
                              itemId: draft.id,
                              targetPersonId: selectedId!,
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop(true);
                            }
                          } on Object catch (_) {
                            if (ctx.mounted) {
                              setState(() => submitting = false);
                            }
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.buttonPublish),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (ok == true && context.mounted) {
    onSaved();
  }
}

String _labelForCandidate({
  required String userId,
  required List<BeaconParticipant> participants,
  required String viewerId,
  required L10n l10n,
}) {
  if (userId == viewerId) {
    return l10n.labelMe;
  }
  BeaconParticipant? match;
  for (final p in participants) {
    if (p.userId == userId) {
      match = p;
      break;
    }
  }
  final title = match?.userTitle.trim() ?? '';
  if (title.isNotEmpty) {
    return title;
  }
  final handle = match?.handle.trim() ?? '';
  if (handle.isNotEmpty) {
    return '@$handle';
  }
  return userId;
}

Future<void> confirmDeletePreparedAsk(
  BuildContext context, {
  required String itemId,
  required VoidCallback onDeleted,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.beaconPreparedAskDeleteConfirmTitle),
      content: Text(l10n.beaconPreparedAskDeleteConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.buttonDelete),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await coordinationCase.deleteDraftAsk(itemId: itemId);
    onDeleted();
  }
}
