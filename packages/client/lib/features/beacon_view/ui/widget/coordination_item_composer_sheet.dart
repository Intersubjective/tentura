import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/coordination_item/ui/widget/ask_composer_fields.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_staleness_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'coordination_target_candidates.dart';

Future<void> showCoordinationItemComposerSheet(
  BuildContext context, {
  required CoordinationItemKind kind,
  required String beaconId,
  required List<BeaconParticipant> participants,
  required String beaconAuthorId,
  required String myUserId,
  required bool isAuthorOrSteward,
  required VoidCallback onSaved, CoordinationItem? existingDraft,
  AskComposerSeed? seed,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final resolvedSeed = existingDraft != null
      ? AskComposerSeed.fromItem(existingDraft)
      : seed;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CoordinationItemComposerBody(
      kind: kind,
      beaconId: beaconId,
      participants: participants,
      beaconAuthorId: beaconAuthorId,
      myUserId: myUserId,
      isAuthorOrSteward: isAuthorOrSteward,
      existingDraft: existingDraft,
      seed: resolvedSeed,
      coordinationCase: coordinationCase,
      l10n: l10n,
    ),
  );
  if (ok == true && context.mounted) {
    onSaved();
  }
}

Future<void> confirmDeleteCoordinationDraft(
  BuildContext context, {
  required CoordinationItemKind kind,
  required String itemId,
  required VoidCallback onDeleted,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.coordinationDeleteDraftTitle),
      content: Text(l10n.coordinationDeleteDraftBody),
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
  if (ok != true || !context.mounted) return;
  switch (kind) {
    case CoordinationItemKind.ask:
      await coordinationCase.deleteDraftAsk(itemId: itemId);
    case CoordinationItemKind.promise:
      await coordinationCase.deleteDraftPromise(itemId: itemId);
    case CoordinationItemKind.blocker:
      await coordinationCase.deleteDraftBlocker(itemId: itemId);
    default:
      return;
  }
  onDeleted();
}

class _CoordinationItemComposerBody extends StatefulWidget {
  const _CoordinationItemComposerBody({
    required this.kind,
    required this.beaconId,
    required this.participants,
    required this.beaconAuthorId,
    required this.myUserId,
    required this.isAuthorOrSteward,
    required this.existingDraft,
    required this.seed,
    required this.coordinationCase,
    required this.l10n,
  });

  final CoordinationItemKind kind;
  final String beaconId;
  final List<BeaconParticipant> participants;
  final String beaconAuthorId;
  final String myUserId;
  final bool isAuthorOrSteward;
  final CoordinationItem? existingDraft;
  final AskComposerSeed? seed;
  final CoordinationItemCase coordinationCase;
  final L10n l10n;

  @override
  State<_CoordinationItemComposerBody> createState() =>
      _CoordinationItemComposerBodyState();
}

class _CoordinationItemComposerBodyState extends State<_CoordinationItemComposerBody> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  String? _selectedTargetId;
  late int _selectedStaleDays;
  bool _submitting = false;

  String? get _linkedMessageId => widget.seed?.linkedMessageId;

  String? get _messagePreview => widget.seed?.messagePreview;

  bool get _isAskOrPromise =>
      widget.kind == CoordinationItemKind.ask ||
      widget.kind == CoordinationItemKind.promise;

  List<String> get _askTargetIds => askTargetUserIds(
        beaconAuthorId: widget.beaconAuthorId,
        participants: widget.participants,
      );

  List<BeaconParticipant> get _promiseTargets => promiseTargetParticipants(
        participants: widget.participants,
        myUserId: widget.myUserId,
        isAuthorOrSteward: widget.isAuthorOrSteward,
      );

  List<BeaconParticipant> get _blockerTargets =>
      participantsForCoordinationTargetPicker(
        participants: widget.participants,
        myUserId: widget.myUserId,
        isAuthorOrSteward: widget.isAuthorOrSteward,
      );

  bool get _hasLegalTargets => switch (widget.kind) {
        CoordinationItemKind.ask => _askTargetIds.isNotEmpty,
        CoordinationItemKind.promise => _promiseTargets.isNotEmpty,
        CoordinationItemKind.blocker => _blockerTargets.isNotEmpty,
        _ => false,
      };

  bool get _willPublish =>
      _selectedTargetId != null && _selectedTargetId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _titleController = TextEditingController(text: seed?.initialTitle ?? '');
    _bodyController = TextEditingController(text: seed?.initialBody ?? '');
    final existingTarget = widget.existingDraft?.targetPersonId?.trim();
    if (existingTarget != null && existingTarget.isNotEmpty) {
      _selectedTargetId = _isValidTarget(existingTarget) ? existingTarget : null;
    }
    _selectedStaleDays = CoordinationStalenessPicker.seedFromDraft(
      widget.existingDraft?.staleAfterDays,
    );
  }

  bool _isValidTarget(String userId) => switch (widget.kind) {
        CoordinationItemKind.ask => _askTargetIds.contains(userId),
        CoordinationItemKind.promise =>
          _promiseTargets.any((p) => p.userId == userId),
        CoordinationItemKind.blocker =>
          _blockerTargets.any((p) => p.userId == userId),
        _ => false,
      };

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _canSubmitContent {
    if (_submitting) return false;
    if (_isAskOrPromise) {
      return AskComposerFields.canSubmit(_bodyController, false);
    }
    return _titleController.text.trim().isNotEmpty;
  }

  Future<void> _onSubmit() async {
    if (!_canSubmitContent) return;
    setState(() => _submitting = true);
    try {
      await _persist();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _persist() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final target = _willPublish ? _selectedTargetId : null;
    final existing = widget.existingDraft;
    final c = widget.coordinationCase;
    final staleDays = _selectedStaleDays;

    switch (widget.kind) {
      case CoordinationItemKind.ask:
        if (existing == null && _willPublish) {
          await c.markAsk(
            beaconId: widget.beaconId,
            title: title,
            targetPersonId: target!,
            body: body,
            linkedMessageId: _linkedMessageId,
            staleAfterDays: staleDays,
          );
        } else if (existing == null) {
          await c.createDraftAsk(
            beaconId: widget.beaconId,
            title: title,
            body: body,
            linkedMessageId: _linkedMessageId,
            targetPersonId: target,
            staleAfterDays: staleDays,
          );
        } else {
          await c.updateDraftAsk(
            itemId: existing.id,
            title: title,
            body: body,
            targetPersonId: target,
            omitTargetPersonId: !_willPublish,
            staleAfterDays: staleDays,
          );
          if (_willPublish) {
            await c.publishDraftAsk(
              itemId: existing.id,
              targetPersonId: target!,
              staleAfterDays: staleDays,
            );
          }
        }
      case CoordinationItemKind.promise:
        if (existing == null && _willPublish) {
          await c.createPromise(
            beaconId: widget.beaconId,
            title: title,
            targetPersonId: target!,
            body: body,
            linkedMessageId: _linkedMessageId,
            staleAfterDays: staleDays,
          );
        } else if (existing == null) {
          await c.createDraftPromise(
            beaconId: widget.beaconId,
            title: title,
            body: body,
            linkedMessageId: _linkedMessageId,
            targetPersonId: target,
            staleAfterDays: staleDays,
          );
        } else {
          await c.updateDraftPromise(
            itemId: existing.id,
            title: title,
            body: body,
            targetPersonId: target,
            omitTargetPersonId: !_willPublish,
            staleAfterDays: staleDays,
          );
          if (_willPublish) {
            await c.publishDraftPromise(
              itemId: existing.id,
              targetPersonId: target!,
              staleAfterDays: staleDays,
            );
          }
        }
      case CoordinationItemKind.blocker:
        if (existing == null && _willPublish) {
          await c.markBlocker(
            beaconId: widget.beaconId,
            title: title,
            body: body.isEmpty ? null : body,
            targetPersonId: target,
            staleAfterDays: staleDays,
          );
        } else if (existing == null) {
          await c.createDraftBlocker(
            beaconId: widget.beaconId,
            title: title,
            body: body.isEmpty ? null : body,
            targetPersonId: target,
            staleAfterDays: staleDays,
          );
        } else {
          await c.updateDraftBlocker(
            itemId: existing.id,
            title: title,
            body: body,
            targetPersonId: target,
            omitTargetPersonId: !_willPublish,
            staleAfterDays: staleDays,
          );
          if (_willPublish) {
            await c.publishDraftBlocker(
              itemId: existing.id,
              staleAfterDays: staleDays,
            );
          }
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    final existing = widget.existingDraft;

    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingSmall,
        right: kSpacingSmall,
        top: kSpacingMedium,
        bottom: bottom + kSpacingMedium,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              coordinationComposerSheetTitle(l10n, widget.kind, existing != null),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: kSpacingSmall),
            if (_isAskOrPromise)
              AskComposerFields(
                l10n: l10n,
                titleController: _titleController,
                bodyController: _bodyController,
                submitting: _submitting,
                messagePreview: _messagePreview,
                onChanged: () => setState(() {}),
              )
            else ...[
              TextField(
                controller: _titleController,
                onChanged: (_) => setState(() {}),
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(labelText: l10n.labelTitle),
                textInputAction: TextInputAction.next,
                enabled: !_submitting,
              ),
              const SizedBox(height: kSpacingSmall),
              TextField(
                controller: _bodyController,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(labelText: l10n.labelBody),
                enabled: !_submitting,
              ),
            ],
            if (_hasLegalTargets) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                coordinationTargetPickerLabel(l10n, widget.kind),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: kSpacingSmall),
              _TargetPicker(
                kind: widget.kind,
                askTargetIds: _askTargetIds,
                participantTargets: widget.kind == CoordinationItemKind.promise
                    ? _promiseTargets
                    : _blockerTargets,
                participants: widget.participants,
                myUserId: widget.myUserId,
                selectedId: _selectedTargetId,
                submitting: _submitting,
                l10n: l10n,
                onSelected: (id) => setState(() => _selectedTargetId = id),
              ),
            ],
            const SizedBox(height: kSpacingSmall),
            CoordinationStalenessPicker(
              l10n: l10n,
              selectedDays: _selectedStaleDays,
              enabled: !_submitting,
              onSelected: (days) => setState(() => _selectedStaleDays = days),
            ),
            if (!_willPublish) ...[
              const SizedBox(height: kSpacingSmall),
              Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(kSpacingSmall),
                  child: Text(
                    l10n.coordinationComposerNoTargetWillSaveDraft,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: kSpacingMedium),
            FilledButton(
              onPressed: !_canSubmitContent ? null : _onSubmit,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _willPublish ? l10n.buttonPublish : l10n.coordinationComposerSaveDraft,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.kind,
    required this.askTargetIds,
    required this.participantTargets,
    required this.participants,
    required this.myUserId,
    required this.selectedId,
    required this.submitting,
    required this.l10n,
    required this.onSelected,
  });

  final CoordinationItemKind kind;
  final List<String> askTargetIds;
  final List<BeaconParticipant> participantTargets;
  final List<BeaconParticipant> participants;
  final String myUserId;
  final String? selectedId;
  final bool submitting;
  final L10n l10n;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = coordinationTargetPickerLabel(l10n, kind);
    final noneLabel = l10n.coordinationComposerTargetNone;

    if (kind == CoordinationItemKind.ask) {
      return DropdownButtonFormField<String?>(
        initialValue: selectedId,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<String?>(
            child: Text(noneLabel),
          ),
          for (final userId in askTargetIds)
            DropdownMenuItem(
              value: userId,
              child: Text(
                coordinationTargetLabel(
                  userId: userId,
                  participants: participants,
                  viewerId: myUserId,
                  l10n: l10n,
                ),
              ),
            ),
        ],
        onChanged: submitting ? null : onSelected,
      );
    }

    return DropdownButtonFormField<String?>(
      initialValue: selectedId != null &&
              participantTargets.any((p) => p.userId == selectedId)
          ? selectedId
          : null,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(
          child: Text(noneLabel),
        ),
        for (final p in participantTargets)
          DropdownMenuItem(
            value: p.userId,
            child: Text(
              coordinationTargetLabel(
                userId: p.userId,
                participants: participants,
                viewerId: myUserId,
                l10n: l10n,
              ),
            ),
          ),
      ],
      onChanged: submitting ? null : onSelected,
    );
  }
}
