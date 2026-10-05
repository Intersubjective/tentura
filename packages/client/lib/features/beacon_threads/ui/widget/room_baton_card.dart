import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The «Who'll take it?» card under a message, as seen by someone who is not
/// the message author: an asked person gets a private answer card, anyone else
/// only a «{name} took it.» chip. It never shows other people's names, tiers
/// or counts.
class RoomBatonCard extends StatelessWidget {
  const RoomBatonCard({
    required this.baton,
    this.onRespond,
    super.key,
  });

  final RoomBatonData baton;

  /// Called with `true` for «Can help» and `false` for «Can't help».
  final void Function(bool canHelp)? onRespond;

  @override
  Widget build(BuildContext context) => switch (baton) {
    final RoomBatonCandidateData candidate => _CandidateBody(
      baton: candidate,
      onRespond: onRespond,
    ),
    final RoomBatonObserverData observer => _TookItChip(
      name: observer.taker.title,
    ),
    // The author's list of answers is a separate card.
    RoomBatonAuthorData() => const SizedBox.shrink(),
  };
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
