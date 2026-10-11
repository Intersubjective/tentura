import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_choose_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Avatar of [userId], resolved from the room's [participants] (falls back to
/// initials of [title] for someone no longer listed).
Widget batonPersonAvatar({
  required String userId,
  required String title,
  required List<BeaconParticipant> participants,
}) {
  for (final p in participants) {
    if (p.userId == userId) {
      return coordinationLogParticipantAvatar(p);
    }
  }
  return TenturaAvatar(
    profile: Profile(id: userId, displayName: title),
    sizeBucket: TenturaAvatarSize.tiny,
  );
}

/// Asks the author to confirm cancelling a baton; `true` when confirmed.
Future<bool> confirmRoomBatonCancel(BuildContext context) async {
  final l10n = L10n.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.batonCancelConfirmTitle),
      content: Text(l10n.batonCancelConfirmBody),
      actions: [
        // Not the system «Cancel»: next to «Cancel the ask» it is ambiguous.
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.batonCancelConfirmKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.batonCancelConfirmAction),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The «Who'll take it?» card inside a baton message bubble, shaped like the
/// poll card: the ask on top, then a body per viewer. An asked person gets a
/// private answer card; anyone else sees only the status and, once chosen,
/// who took it — never other people's names, tiers or counts. The baton
/// author sees every asked person's answer and chooses who takes it.
class RoomBatonCard extends StatelessWidget {
  const RoomBatonCard({
    required this.baton,
    this.title = '',
    this.participants = const [],
    this.onRespond,
    this.onSelect,
    this.onCancel,
    super.key,
  });

  final RoomBatonData baton;

  /// The ask (the message body); empty when the baton only replies to a
  /// message, whose quote then says what it is about.
  final String title;

  /// Room participants, for avatars.
  final List<BeaconParticipant> participants;

  /// Called with `true` for «Can help» and `false` for «Can't help».
  final void Function(bool canHelp)? onRespond;

  /// Author only: called with the chosen user id, or `null` to let the server
  /// pick.
  final void Function(String? userId)? onSelect;

  /// Author only: called once the author confirmed the cancel.
  final void Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final ask = title.trim();
    final body = switch (baton) {
      final RoomBatonCandidateData candidate => _CandidateBody(
        baton: candidate,
        onRespond: onRespond,
      ),
      final RoomBatonObserverData observer => _StatusLine(
        status: observer.status,
        taker: observer.taker,
        participants: participants,
      ),
      final RoomBatonAuthorData author => _AuthorBody(
        baton: author,
        participants: participants,
        onSelect: onSelect,
        onCancel: onCancel,
      ),
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    right: tt.rowGap,
                    top: tt.tightGap,
                  ),
                  child: Icon(
                    Icons.pan_tool_alt_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    ask.isEmpty ? L10n.of(context)!.batonCreateTitle : ask,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tt.rowGap),
            body,
          ],
        ),
      ),
    );
  }
}

/// One line for a final (or, for observers, still open) baton: «Looking for
/// someone», «{name} took it.» with their avatar, or «Cancelled.».
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.status,
    required this.participants,
    this.taker,
  });

  final RoomBatonStatus status;
  final RoomBatonTaker? taker;
  final List<BeaconParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final taker = this.taker;
    if (status == RoomBatonStatus.taken && taker != null) {
      return Row(
        children: [
          batonPersonAvatar(
            userId: taker.id,
            title: taker.title,
            participants: participants,
          ),
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Text(
              l10n.batonTookIt(taker.title),
              style: TenturaText.body(tt.text),
            ),
          ),
        ],
      );
    }
    return Text(
      status == RoomBatonStatus.cancelled
          ? l10n.batonCancelledLine
          : l10n.batonObserverCollecting,
      style: TenturaText.bodySmall(tt.textMuted),
    );
  }
}

class _AuthorBody extends StatelessWidget {
  const _AuthorBody({
    required this.baton,
    required this.participants,
    this.onSelect,
    this.onCancel,
  });

  final RoomBatonAuthorData baton;
  final List<BeaconParticipant> participants;
  final void Function(String? userId)? onSelect;
  final void Function()? onCancel;

  Future<void> _confirmCancel(BuildContext context) async {
    if (await confirmRoomBatonCancel(context)) onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (baton.status != RoomBatonStatus.collecting) {
      return _StatusLine(
        status: baton.status,
        taker: baton.taker,
        participants: participants,
      );
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final mutedBody = TenturaText.bodySmall(tt.textMuted);
    final showTiers = baton.candidates.map((c) => c.tier).toSet().length > 1;
    final canChoose = baton.candidates.any(
      (c) => c.response == RoomBatonResponse.canHelp,
    );
    final select = onSelect;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.batonAuthorTitle, style: mutedBody),
        SizedBox(height: tt.tightGap),
        for (final candidate in baton.candidates)
          Padding(
            padding: EdgeInsets.only(bottom: tt.tightGap),
            child: Row(
              children: [
                batonPersonAvatar(
                  userId: candidate.userId,
                  title: candidate.title,
                  participants: participants,
                ),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Text(
                    candidate.title,
                    style: TenturaText.bodySmall(tt.text),
                  ),
                ),
                if (showTiers) ...[
                  Text(l10n.batonTierLabel(candidate.tier), style: mutedBody),
                  SizedBox(width: tt.rowGap),
                ],
                Text(
                  switch (candidate.response) {
                    RoomBatonResponse.canHelp => l10n.batonStatusCanHelp,
                    RoomBatonResponse.waiting => l10n.batonStatusWaiting,
                    RoomBatonResponse.cantHelp => l10n.batonStatusCantHelp,
                  },
                  style: TenturaText.bodySmall(
                    candidate.response == RoomBatonResponse.canHelp
                        ? tt.good
                        : tt.textMuted,
                  ),
                ),
              ],
            ),
          ),
        if (baton.allAnswered) ...[
          SizedBox(height: tt.tightGap),
          Text(
            l10n.batonAllAnswered,
            style: TenturaText.body(tt.attentionHighlight),
          ),
        ],
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.rowGap,
          runSpacing: tt.tightGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: canChoose && select != null
                  ? () => showRoomBatonChooseSheet(
                      context,
                      candidates: baton.candidates,
                      participants: participants,
                      onSelect: select,
                    )
                  : null,
              child: Text(l10n.batonChooseNow),
            ),
            if (!canChoose) Text(l10n.batonNobodyYet, style: mutedBody),
            TextButton(
              onPressed: onCancel == null
                  ? null
                  : () => _confirmCancel(context),
              child: Text(l10n.batonCancel),
            ),
          ],
        ),
      ],
    );
  }
}

class _CandidateBody extends StatelessWidget {
  const _CandidateBody({required this.baton, this.onRespond});

  final RoomBatonCandidateData baton;
  final void Function(bool canHelp)? onRespond;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final mutedBody = TenturaText.bodySmall(tt.textMuted);

    final outcome =
        baton.outcome ??
        (baton.status == RoomBatonStatus.cancelled
            ? RoomBatonOutcome.closed
            : null);
    if (baton.status != RoomBatonStatus.collecting) {
      if (outcome == null) return const SizedBox.shrink();
      return Text(
        switch (outcome) {
          RoomBatonOutcome.you => l10n.batonOutcomeYou,
          RoomBatonOutcome.someoneElse => l10n.batonOutcomeSomeoneElse,
          RoomBatonOutcome.closed => l10n.batonOutcomeClosed,
        },
        style: mutedBody,
      );
    }

    final answer = baton.myResponse;
    final answered =
        answer == RoomBatonResponse.canHelp ||
        answer == RoomBatonResponse.cantHelp;
    final canHelpChosen = answer == RoomBatonResponse.canHelp;
    final cantHelpChosen = answer == RoomBatonResponse.cantHelp;
    final respond = onRespond;

    Widget answerButton({
      required bool canHelp,
      required bool chosen,
      required String label,
    }) {
      final onPressed = respond == null ? null : () => respond(canHelp);
      final text = Text(label);
      return chosen
          ? FilledButton(onPressed: onPressed, child: text)
          : OutlinedButton(onPressed: onPressed, child: text);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answered
              ? l10n.batonCandidateAnswered(
                  canHelpChosen
                      ? l10n.batonCandidateCanHelp
                      : l10n.batonCandidateCantHelp,
                )
              : l10n.batonCandidatePrompt,
          style: TenturaText.body(tt.text),
        ),
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.rowGap,
          runSpacing: tt.tightGap,
          children: [
            answerButton(
              canHelp: true,
              chosen: canHelpChosen,
              label: l10n.batonCandidateCanHelp,
            ),
            answerButton(
              canHelp: false,
              chosen: cantHelpChosen,
              label: l10n.batonCandidateCantHelp,
            ),
          ],
        ),
        if (!answered) ...[
          SizedBox(height: tt.tightGap),
          Text(l10n.batonCandidateAvailabilityNote, style: mutedBody),
        ],
      ],
    );
  }
}
