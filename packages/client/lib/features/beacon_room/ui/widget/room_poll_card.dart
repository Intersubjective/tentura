import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

class RoomPollCard extends StatelessWidget {
  const RoomPollCard({
    required this.poll,
    required this.onVote,
    super.key,
  });

  final RoomPollData poll;

  /// Null when the user has already voted (card is non-interactive).
  final void Function(String variantId)? onVote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final cs = theme.colorScheme;
    final voted = poll.hasVoted;

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(kSpacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poll icon + question
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: kSpacingSmall, top: 2),
                  child: Icon(Icons.poll, size: 18, color: cs.primary),
                ),
                Expanded(
                  child: Text(
                    poll.question,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpacingSmall),

            // Variants
            ...poll.variants.map((v) {
              final isMyVote = poll.myVariantId == v.id;
              final pct = poll.percentageFor(v.id);
              final pctInt = (pct * 100).round();

              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: voted
                    ? _VotedVariantRow(
                        label: v.description,
                        votesCount: v.votesCount,
                        percentage: pct,
                        pctInt: pctInt,
                        isMyVote: isMyVote,
                        theme: theme,
                      )
                    : _UnvotedVariantRow(
                        label: v.description,
                        onTap: () => onVote?.call(v.id),
                        theme: theme,
                      ),
              );
            }),

            const SizedBox(height: kSpacingSmall),

            // Total votes footer
            Text(
              l10n.beaconRoomPollVotesCount(poll.totalVotes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnvotedVariantRow extends StatelessWidget {
  const _UnvotedVariantRow({
    required this.label,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final VoidCallback? onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.radio_button_unchecked, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: kSpacingSmall),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    ),
  );
}

class _VotedVariantRow extends StatelessWidget {
  const _VotedVariantRow({
    required this.label,
    required this.votesCount,
    required this.percentage,
    required this.pctInt,
    required this.isMyVote,
    required this.theme,
  });

  final String label;
  final int votesCount;
  final double percentage;
  final int pctInt;
  final bool isMyVote;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Container(
      decoration: isMyVote
          ? BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isMyVote ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: isMyVote ? cs.primary : cs.outline,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isMyVote ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                '$pctInt%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isMyVote ? cs.primary : cs.outline,
                  fontWeight: isMyVote ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($votesCount)',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isMyVote ? cs.primary : cs.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
