import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'attention_visibility_ack.dart';

/// Updates feed row for invite-accepted receipts with optional seed-routing prompt.
class InviteAcceptedReceiptCard extends StatefulWidget {
  const InviteAcceptedReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onSettle,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onSettle;

  @override
  State<InviteAcceptedReceiptCard> createState() =>
      _InviteAcceptedReceiptCardState();
}

enum _PromptLoadPhase { loading, ready, error }

class _InviteAcceptedReceiptCardState extends State<InviteAcceptedReceiptCard> {
  static const _maxSeedSelections = 3;

  _PromptLoadPhase _phase = _PromptLoadPhase.loading;
  InviteSeedPromptState? _promptState;
  String _inviteeDisplayName = '';
  Set<String> _selectedSlugs = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPromptData());
  }

  String? get _subjectId =>
      widget.receipt.actorUserId ?? widget.receipt.targetEntityId;

  Future<void> _loadPromptData() async {
    final subjectId = _subjectId;
    if (subjectId == null || subjectId.isEmpty) {
      if (mounted) setState(() => _phase = _PromptLoadPhase.error);
      return;
    }

    try {
      final results = await Future.wait<Object>([
        GetIt.I<ProfileRepositoryPort>()
            .fetchById(subjectId)
            .catchError((_) => Profile(id: subjectId)),
        GetIt.I<CapabilityRepositoryPort>().fetchInviteSeedPromptState(
          subjectId,
        ),
      ]);
      if (!mounted) return;
      final profile = results[0] as Profile;
      final promptState = results[1] as InviteSeedPromptState;
      final l10n = L10n.of(context)!;
      setState(() {
        _inviteeDisplayName = profile.displayLabel(l10n.unknownPerson);
        _promptState = promptState;
        _phase = _PromptLoadPhase.ready;
      });
    } on Object {
      if (mounted) setState(() => _phase = _PromptLoadPhase.error);
    }
  }

  Future<void> _submit() async {
    final subjectId = _subjectId;
    if (subjectId == null || _selectedSlugs.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await GetIt.I<CapabilityRepositoryPort>().inviteSeedPromptAnswer(
        subjectId: subjectId,
        slugs: _selectedSlugs.toList(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _promptState = _promptState?.copyWith(
          state: PromptStateValue.answered,
        );
      });
    } on Object {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _skip() async {
    final subjectId = _subjectId;
    if (subjectId == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await GetIt.I<CapabilityRepositoryPort>().inviteSeedPromptSkip(subjectId);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _promptState = _promptState?.copyWith(state: PromptStateValue.skipped);
      });
    } on Object {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final isUnread = !receipt.isSeen;
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      l10n: l10n,
    );
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';
    final showPicker =
        _phase == _PromptLoadPhase.ready &&
        _promptState?.state == PromptStateValue.pending;

    return AttentionVisibilityAck(
      receiptId: receipt.id,
      isSeen: receipt.isSeen,
      onAcknowledge: (_) async => widget.onMarkSeen(),
      child: Semantics(
        identifier: TestIds.updatesReceipt(receipt.id),
        label: copy.title,
        button: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              onTap: widget.onTap,
              contentPadding: tt.cardPadding,
              leading: Icon(
                Icons.people_alt_outlined,
                color: isUnread ? tt.info : tt.textMuted,
                size: tt.iconSize,
              ),
              title: Text(
                copy.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    TenturaText.title(
                      isUnread ? colors.onSurface : tt.textMuted,
                    ).copyWith(
                      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
              subtitle: Text(
                copy.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: absoluteTime,
                    child: Text(
                      ageLabel,
                      style: TenturaText.bodySmall(tt.textFaint),
                    ),
                  ),
                  if (isUnread)
                    IconButton(
                      tooltip: l10n.updatesMarkSeen,
                      onPressed: widget.onMarkSeen,
                      icon: const Icon(Icons.done_outlined),
                    ),
                ],
              ),
            ),
            if (_phase == _PromptLoadPhase.loading)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.tightGap,
                ),
                child: const Center(
                  child: CircularProgressIndicator.adaptive(),
                ),
              )
            else if (_phase == _PromptLoadPhase.error)
              Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  bottom: tt.cardPadding.bottom,
                ),
                child: Text(
                  l10n.inviteSeedPromptLoadError,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              )
            else if (showPicker)
              Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  bottom: tt.cardPadding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.inviteSeedPromptQuestion(_inviteeDisplayName),
                      style: TenturaText.body(colors.onSurface),
                    ),
                    SizedBox(height: tt.rowGap),
                    CapabilityChipSet(
                      selectedSlugs: _selectedSlugs,
                      maxSelection: _maxSeedSelections,
                      onChanged: (slugs) => setState(() => _selectedSlugs = slugs),
                    ),
                    SizedBox(height: tt.rowGap),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _selectedSlugs.isEmpty || _submitting
                              ? null
                              : _submit,
                          child: _submitting
                              ? SizedBox.square(
                                  dimension: tt.iconSize * 0.75,
                                  child:
                                      const CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                      ),
                                )
                              : Text(l10n.inviteSeedPromptSubmit),
                        ),
                        SizedBox(width: tt.tightGap),
                        TextButton(
                          onPressed: _submitting ? null : _skip,
                          child: Text(l10n.inviteSeedPromptSkip),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
