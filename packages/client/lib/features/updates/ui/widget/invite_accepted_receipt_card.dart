import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_setup_sheet.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_bounded_shell.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Compact Updates row for an accepted invitation.
class InviteAcceptedReceiptCard extends StatefulWidget {
  const InviteAcceptedReceiptCard({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    this.promptProjection = const PromptProjection.unknown(),
    this.onRetryPromptFetch,
    this.onPromptSettled,
    this.setupCase,
    this.activityOfferBoundedShell = false,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final Future<void> Function() onMarkSeen;
  final VoidCallback onMarkUnseen;
  final PromptProjection promptProjection;
  final Future<void> Function(String subjectId)? onRetryPromptFetch;
  final void Function(String subjectId, InviteSeedPromptState state)?
  onPromptSettled;
  final InviteAcceptedSetupPort? setupCase;

  /// When true, render inside [ActivityOfferBoundedShell] (Activity pinned zone).
  final bool activityOfferBoundedShell;

  @override
  State<InviteAcceptedReceiptCard> createState() =>
      _InviteAcceptedReceiptCardState();
}

enum _PromptLoadPhase { notApplicable, loading, pending, settled, error }

class _InviteAcceptedReceiptCardState extends State<InviteAcceptedReceiptCard> {
  Profile? _inviteeProfile;
  bool _openingSetup = false;
  bool _modalOutcomeMarkedSeen = false;

  InviteAcceptedSetupPort get _setupCase =>
      widget.setupCase ?? GetIt.I<InviteAcceptedSetupPort>();

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
    _startProfileLoad();
  }

  @override
  void didUpdateWidget(InviteAcceptedReceiptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.id != widget.receipt.id ||
        oldWidget.receipt.presentationPayloadJson !=
            widget.receipt.presentationPayloadJson) {
      _inviteeProfile = null;
      _openingSetup = false;
      _modalOutcomeMarkedSeen = false;
      _startProfileLoad();
    }
  }

  void _startProfileLoad() {
    final subjectId = _subjectId;
    if (subjectId == null || subjectId.isEmpty) return;
    unawaited(_loadProfile(subjectId));
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

  _PromptLoadPhase _promptPhase() {
    if (!_isNewAccount || _subjectId == null) {
      return _PromptLoadPhase.notApplicable;
    }
    return switch (widget.promptProjection) {
      PromptProjectionUnknown() => _PromptLoadPhase.loading,
      PromptProjectionFailed() => _PromptLoadPhase.error,
      PromptProjectionKnown(:final state) =>
        state.state == PromptStateValue.pending
            ? _PromptLoadPhase.pending
            : _PromptLoadPhase.settled,
    };
  }

  Future<void> _openSetup() async {
    final subjectId = _subjectId;
    final prompt = switch (widget.promptProjection) {
      PromptProjectionKnown(:final state) => state,
      _ => null,
    };
    if (_openingSetup ||
        subjectId == null ||
        prompt == null ||
        _promptPhase() != _PromptLoadPhase.pending) {
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
    setState(() => _inviteeProfile = result.profile);
    widget.onPromptSettled?.call(
      subjectId,
      prompt.copyWith(
        state: result.action == InviteAcceptedSetupAction.saved
            ? PromptStateValue.answered
            : PromptStateValue.skipped,
      ),
    );
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
    final copy = _displayCopy(l10n);
    final phase = _promptPhase();
    final Widget? action;
    if (phase == _PromptLoadPhase.pending) {
      action = TenturaTextAction(
        label: l10n.inviteAcceptedSetupAddDetails,
        semanticsIdentifier: TestIds.inviteAcceptedSetupOpen,
        flushStart: true,
        onPressed: _openingSetup ? null : _openSetup,
      );
    } else if (phase == _PromptLoadPhase.error) {
      action = TenturaTextAction(
        label: l10n.inviteAcceptedSetupRetry,
        semanticsIdentifier: TestIds.inviteAcceptedSetupRetry,
        tone: TenturaTone.danger,
        flushStart: true,
        onPressed: () {
          final subjectId = _subjectId;
          final retry = widget.onRetryPromptFetch;
          if (subjectId != null && retry != null) {
            unawaited(retry(subjectId));
          }
        },
      );
    } else {
      action = null;
    }

    if (widget.activityOfferBoundedShell) {
      final subjectId = _subjectId;
      final profile =
          _inviteeProfile ??
          (subjectId != null
              ? Profile(id: subjectId, displayName: copy.title)
              : null);
      final tt = context.tt;
      return ActivityOfferBoundedShell(
        leading: profile != null
            ? TenturaAvatar.medium(
                profile: profile,
                onTap: () =>
                    context.read<ScreenCubit>().showProfile(profile.id),
              )
            : SizedBox.square(dimension: tt.avatarSize),
        headline: copy.title,
        whyLine: copy.body,
        createdAt: receipt.createdAt,
        showUnseenDot: !receipt.isSeen,
        onBodyTap: widget.onTap,
        footer: action != null
            ? Padding(
                padding: EdgeInsets.only(left: tt.tightGap),
                child: action,
              )
            : null,
      );
    }

    return UpdatesFeedTile(
      receipt: receipt,
      actor: _inviteeProfile,
      onTap: widget.onTap,
      onMarkSeen: () => unawaited(widget.onMarkSeen()),
      onMarkUnseen: widget.onMarkUnseen,
      headlineOverride: copy.title,
      bodyOverride: copy.body,
      action: action,
    );
  }
}
