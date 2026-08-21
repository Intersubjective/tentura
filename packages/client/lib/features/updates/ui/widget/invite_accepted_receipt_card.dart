import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_setup_sheet.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Compact Updates row for an accepted invitation.
class InviteAcceptedReceiptCard extends StatefulWidget {
  const InviteAcceptedReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    this.setupCase,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final Future<void> Function() onMarkSeen;
  final InviteAcceptedSetupPort? setupCase;

  @override
  State<InviteAcceptedReceiptCard> createState() =>
      _InviteAcceptedReceiptCardState();
}

enum _PromptLoadPhase { notApplicable, loading, pending, settled, error }

class _InviteAcceptedReceiptCardState extends State<InviteAcceptedReceiptCard> {
  late _PromptLoadPhase _promptPhase;
  InviteSeedPromptState? _promptState;
  Profile? _inviteeProfile;
  bool _openingSetup = false;
  bool _modalOutcomeMarkedSeen = false;

  InviteAcceptedSetupPort get _setupCase =>
      widget.setupCase ?? GetIt.I<InviteAcceptedSetupCase>();

  String? get _subjectId =>
      widget.receipt.actorUserId ?? widget.receipt.targetEntityId;

  bool get _isNewAccount =>
      inviteOriginFromPresentationPayload(
        widget.receipt.presentationPayloadJson,
      ) ==
      'new_account';

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void didUpdateWidget(InviteAcceptedReceiptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.id != widget.receipt.id ||
        oldWidget.receipt.presentationPayloadJson !=
            widget.receipt.presentationPayloadJson) {
      _promptState = null;
      _inviteeProfile = null;
      _openingSetup = false;
      _modalOutcomeMarkedSeen = false;
      _startLoading();
    }
  }

  void _startLoading() {
    _promptPhase = _isNewAccount
        ? _PromptLoadPhase.loading
        : _PromptLoadPhase.notApplicable;
    final subjectId = _subjectId;
    if (subjectId == null || subjectId.isEmpty) {
      _promptPhase = _PromptLoadPhase.notApplicable;
      return;
    }
    unawaited(_loadProfile(subjectId));
    if (_isNewAccount) unawaited(_loadPrompt(subjectId));
  }

  Future<void> _loadProfile(String subjectId) async {
    try {
      final profile = await _setupCase.fetchProfile(subjectId);
      if (!mounted || subjectId != _subjectId) return;
      setState(() => _inviteeProfile = profile);
    } on Object {
      // Receipt copy remains usable when the optional profile projection fails.
    }
  }

  Future<void> _loadPrompt(String subjectId) async {
    if (mounted) {
      setState(() => _promptPhase = _PromptLoadPhase.loading);
    }
    try {
      final prompt = await _setupCase.fetchPrompt(subjectId);
      if (!mounted || subjectId != _subjectId) return;
      setState(() {
        _promptState = prompt;
        _promptPhase = prompt.state == PromptStateValue.pending
            ? _PromptLoadPhase.pending
            : _PromptLoadPhase.settled;
      });
    } on Object {
      if (!mounted || subjectId != _subjectId) return;
      setState(() => _promptPhase = _PromptLoadPhase.error);
    }
  }

  Future<void> _openSetup() async {
    final subjectId = _subjectId;
    final prompt = _promptState;
    if (_openingSetup ||
        subjectId == null ||
        prompt == null ||
        _promptPhase != _PromptLoadPhase.pending) {
      return;
    }
    final l10n = L10n.of(context)!;
    final fallbackCopy = _displayCopy(l10n);
    final profile =
        _inviteeProfile ??
        Profile(id: subjectId, displayName: fallbackCopy.title);
    setState(() => _openingSetup = true);
    final result = await InviteAcceptedSetupSheet.show(
      context: context,
      subjectId: subjectId,
      profile: profile,
      prompt: prompt,
      setupCase: _setupCase,
    );
    if (!mounted) return;
    setState(() => _openingSetup = false);
    if (result == null) {
      // A rename may already have persisted before capability submission
      // failed. Reconcile that projection without settling the prompt.
      unawaited(_loadProfile(subjectId));
      return;
    }
    setState(() {
      _inviteeProfile = result.profile;
      _promptState = prompt.copyWith(
        state: result.action == InviteAcceptedSetupAction.saved
            ? PromptStateValue.answered
            : PromptStateValue.skipped,
      );
      _promptPhase = _PromptLoadPhase.settled;
    });
    await _markSeenForModalOutcome();
  }

  Future<void> _markSeenForModalOutcome() async {
    if (_modalOutcomeMarkedSeen) return;
    _modalOutcomeMarkedSeen = true;
    await widget.onMarkSeen();
  }

  InviteAcceptedDisplayCopy _displayCopy(L10n l10n) =>
      resolveInviteAcceptedDisplayCopy(
        receiptTitle: widget.receipt.title,
        receiptBody: widget.receipt.body,
        presentationPayloadJson: widget.receipt.presentationPayloadJson,
        presentationKey: widget.receipt.presentationKey,
        l10n: l10n,
        profile: _inviteeProfile,
      );

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final isUnread = !receipt.isSeen;
    final copy = _displayCopy(l10n);
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';

    return Semantics(
      identifier: TestIds.updatesReceipt(receipt.id),
      label: copy.title,
      button: true,
      child: ListTile(
        onTap: widget.onTap,
        contentPadding: tt.cardPadding,
        leading: Icon(
          Icons.people_alt_outlined,
          color: isUnread ? tt.info : tt.textMuted,
          size: tt.iconSize,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
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
            if (copy.secondary.isNotEmpty)
              Text(
                copy.secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            if (_promptPhase == _PromptLoadPhase.pending)
              TenturaTextAction(
                label: l10n.inviteAcceptedSetupAddDetails,
                semanticsIdentifier: TestIds.inviteAcceptedSetupOpen,
                onPressed: _openingSetup ? null : _openSetup,
              )
            else if (_promptPhase == _PromptLoadPhase.error)
              TenturaTextAction(
                label: l10n.inviteAcceptedSetupRetry,
                semanticsIdentifier: TestIds.inviteAcceptedSetupRetry,
                tone: TenturaTone.danger,
                onPressed: () {
                  final subjectId = _subjectId;
                  if (subjectId != null) unawaited(_loadPrompt(subjectId));
                },
              ),
          ],
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
                onPressed: () => unawaited(widget.onMarkSeen()),
                icon: const Icon(Icons.done_outlined),
              ),
          ],
        ),
      ),
    );
  }
}
