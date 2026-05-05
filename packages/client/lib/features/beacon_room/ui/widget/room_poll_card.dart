import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

typedef _OnVote = void Function(List<String> variantIds, {int? score});

class RoomPollCard extends StatefulWidget {
  const RoomPollCard({
    required this.poll,
    this.onVote,
    this.participants = const [],
    super.key,
  });

  final RoomPollData poll;

  /// Null when the viewer cannot vote (e.g. not a member).
  final _OnVote? onVote;

  /// Room participants used to resolve voter display names for open polls.
  final List<BeaconParticipant> participants;

  @override
  State<RoomPollCard> createState() => _RoomPollCardState();
}

class _RoomPollCardState extends State<RoomPollCard> {
  // For multiple: currently selected variant IDs (pending submit)
  late Set<String> _pendingMultiple;

  // For range: score per variant (null = not yet set)
  late Map<String, int> _pendingRange;

  // Whether we're showing the edit view again after revote
  bool _revoting = false;

  @override
  void initState() {
    super.initState();
    _pendingMultiple = widget.poll.myVariantIds.toSet();
    _pendingRange = {};
  }

  bool get _isVoted => !_revoting && widget.poll.hasVoted;

  void _submitVote(List<String> variantIds, {int? score}) {
    setState(() => _revoting = false);
    widget.onVote?.call(variantIds, score: score);
  }

  Widget _buildSingleUnvoted(ThemeData theme, String variantId, String label) =>
      InkWell(
        onTap: widget.onVote == null ? null : () => _submitVote([variantId]),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Icon(
                Icons.radio_button_unchecked,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      );

  Widget _buildMultipleUnvoted(ThemeData theme, String variantId, String label) =>
      InkWell(
        onTap: () => setState(() {
          if (_pendingMultiple.contains(variantId)) {
            _pendingMultiple.remove(variantId);
          } else {
            _pendingMultiple.add(variantId);
          }
        }),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Icon(
                _pendingMultiple.contains(variantId)
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
                color: _pendingMultiple.contains(variantId)
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      );

  Widget _buildRangeUnvoted(ThemeData theme, String variantId, String label) {
    final score = _pendingRange[variantId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$score',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          Slider(
            value: (score ?? 0).toDouble(),
            min: 0,
            max: 5,
            divisions: 5,
            onChanged: (v) => setState(
              () => _pendingRange[variantId] = v.round(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVotedRow(
    ThemeData theme,
    RoomPollVariant v,
    bool showVoters,
    Map<String, String> voterNames,
  ) {
    final cs = theme.colorScheme;
    final isMine = widget.poll.isMyVote(v.id);
    final poll = widget.poll;

    double pct;
    String primaryLabel;
    if (poll.pollType == PollType.range) {
      pct = (v.avgScore ?? 0) / 5;
      primaryLabel = v.avgScore != null
          ? '${v.avgScore!.toStringAsFixed(1)}/5'
          : '—';
    } else {
      pct = poll.percentageFor(v.id);
      primaryLabel = '${(pct * 100).round()}%';
    }

    return Container(
      decoration: isMine
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
              if (poll.pollType == PollType.single)
                Icon(
                  isMine ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: isMine ? cs.primary : cs.outline,
                )
              else if (poll.pollType == PollType.multiple)
                Icon(
                  isMine ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: isMine ? cs.primary : cs.outline,
                )
              else
                Icon(Icons.bar_chart, size: 20, color: cs.outline),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  v.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isMine ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                primaryLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isMine ? cs.primary : cs.outline,
                  fontWeight: isMine ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${v.votesCount})',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isMine ? cs.primary : cs.secondary,
              ),
            ),
          ),
          if (showVoters && v.voterIds != null && v.voterIds!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final uid in v.voterIds!)
                  Chip(
                    label: Text(
                      voterNames[uid] ?? uid.substring(0, 6),
                      style: theme.textTheme.labelSmall,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final cs = theme.colorScheme;
    final poll = widget.poll;
    final voted = _isVoted;
    final showVoters = !poll.isAnonymous && poll.hasVoted;

    final voterNames = <String, String>{
      for (final p in widget.participants) p.userId: p.userTitle,
    };

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
            ...poll.variants.map((v) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: voted
                  ? _buildVotedRow(theme, v, showVoters, voterNames)
                  : switch (poll.pollType) {
                      PollType.multiple => _buildMultipleUnvoted(theme, v.id, v.description),
                      PollType.range => _buildRangeUnvoted(theme, v.id, v.description),
                      _ => _buildSingleUnvoted(theme, v.id, v.description),
                    },
            )),

            // Submit button for multiple / range
            if (!voted && poll.pollType != PollType.single) ...[
              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: switch (poll.pollType) {
                  PollType.multiple when _pendingMultiple.isNotEmpty => () {
                      // For multiple: we toggle variantIds one-by-one per tap,
                      // but here we submit the full selection at once.
                      // Server's upsert handles the full set by toggling.
                      // We call onVote for each selected variant so server toggles correctly.
                      _submitVote(_pendingMultiple.toList());
                    },
                  PollType.range when _pendingRange.isNotEmpty => () {
                      // Submit variants that have been scored (score >= 1)
                      final scored = _pendingRange.entries
                          .where((e) => e.value >= 1)
                          .toList();
                      if (scored.isEmpty) return;
                      // Send each variant separately with its score
                      for (final entry in scored) {
                        widget.onVote?.call([entry.key], score: entry.value);
                      }
                      setState(() => _revoting = false);
                    },
                  _ => null,
                },
                child: Text(
                  poll.pollType == PollType.range
                      ? 'Submit ratings'
                      : 'Submit',
                ),
              ),
            ],

            const SizedBox(height: kSpacingSmall),

            // Footer: vote count + revote button
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.beaconRoomPollVotesCount(poll.totalVotes),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
                if (voted && poll.allowRevote && widget.onVote != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _revoting = true;
                      _pendingMultiple = poll.myVariantIds.toSet();
                      _pendingRange = {};
                    }),
                    child: const Text('Change answer'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
