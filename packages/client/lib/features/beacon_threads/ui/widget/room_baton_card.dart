import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_choose_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The «Who'll take it?» card under a message. An asked person gets a private
/// answer card, anyone else only a «{name} took it.» chip — neither shows other
/// people's names, tiers or counts. The message author sees every asked
/// person's answer and chooses who takes it.
class RoomBatonCard extends StatelessWidget {
  const RoomBatonCard({
    required this.baton,
    this.onRespond,
    this.onSelect,
    this.onCancel,
    super.key,
  });

  final RoomBatonData baton;

  /// Called with `true` for «Can help» and `false` for «Can't help».
  final void Function(bool canHelp)? onRespond;

  /// Author only: called with the chosen user id, or `null` to let the server
  /// pick.
  final void Function(String? userId)? onSelect;

  /// Author only: called once the author confirmed the cancel.
  final void Function()? onCancel;

  @override
  Widget build(BuildContext context) => switch (baton) {
    final RoomBatonCandidateData candidate => _CandidateBody(
      baton: candidate,
      onRespond: onRespond,
    ),
    final RoomBatonObserverData observer => _TookItChip(
      name: observer.taker.title,
    ),
    final RoomBatonAuthorData author => _AuthorBody(
      baton: author,
      onSelect: onSelect,
      onCancel: onCancel,
    ),
  };
}

class _AuthorBody extends StatelessWidget {
  const _AuthorBody({required this.baton, this.onSelect, this.onCancel});

  final RoomBatonAuthorData baton;
  final void Function(String? userId)? onSelect;
  final void Function()? onCancel;

  Future<void> _confirmCancel(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.batonCancelConfirmTitle),
        content: Text(l10n.batonCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.batonCancelConfirmAction),
          ),
        ],
      ),
    );
    if (ok == true) onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final taker = baton.taker;
    if (baton.status == RoomBatonStatus.taken) {
      return taker == null
          ? const SizedBox.shrink()
          : _TookItChip(name: taker.title);
    }
    if (baton.status != RoomBatonStatus.collecting) {
      return const SizedBox.shrink();
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
        Text(l10n.batonAuthorTitle, style: TenturaText.body(tt.text)),
        SizedBox(height: tt.tightGap),
        for (final candidate in baton.candidates)
          Padding(
            padding: EdgeInsets.only(bottom: tt.tightGap),
            child: Row(
              children: [
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

class _TookItChip extends StatelessWidget {
  const _TookItChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Chip(
      avatar: Icon(Icons.check_circle_outline, size: 16, color: tt.textMuted),
      label: Text(
        L10n.of(context)!.batonTookIt(name),
        style: TenturaText.bodySmall(tt.textMuted),
      ),
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
