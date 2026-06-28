import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

class RoomPollCard extends StatefulWidget {
  const RoomPollCard({
    required this.poll,
    this.onVote,
    this.participants = const [],
    super.key,
  });

  final RoomPollData poll;

  /// Null when the viewer cannot vote (e.g. not a member).
  final void Function(List<String> variantIds, {int? score})? onVote;

  /// Room participants used to resolve voter display names for open polls.
  final List<BeaconParticipant> participants;

  @override
  State<RoomPollCard> createState() => _RoomPollCardState();
}

class _RoomPollCardState extends State<RoomPollCard> {
  static const _kVoterAvatarSize = 18.0;
  static const _kMaxShownVoterAvatars = 8;

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

  Widget _buildMultipleUnvoted(
    ThemeData theme,
    String variantId,
    String label,
  ) => InkWell(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
            max: 5,
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
    Map<String, BeaconParticipant> participantsByUserId,
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
                  isMine
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
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
            _buildVoterAvatarsWrap(
              theme: theme,
              voterIds: v.voterIds!,
              participantsByUserId: participantsByUserId,
            ),
          ],
        ],
      ),
    );
  }

  Profile _profileForParticipant(BeaconParticipant p) {
    return Profile(
      id: p.userId,
      displayName: p.userTitle,
      image: p.userHasPicture && p.userImageId.isNotEmpty
          ? ImageEntity(
              id: p.userImageId,
              authorId: p.userId,
              blurHash: p.userBlurHash,
              height: p.userPicHeight,
              width: p.userPicWidth,
            )
          : null,
    );
  }

  Widget _buildVoterAvatarsWrap({
    required ThemeData theme,
    required List<String> voterIds,
    required Map<String, BeaconParticipant> participantsByUserId,
  }) {
    final cs = theme.colorScheme;
    final shown = voterIds.take(_kMaxShownVoterAvatars).toList();
    final overflow = voterIds.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final uid in shown)
          Builder(
            builder: (context) {
              final p = participantsByUserId[uid];
              final title = p?.userTitle.trim().isNotEmpty ?? false
                  ? p!.userTitle
                  : uid.substring(0, 6);
              final profile = p == null
                  ? Profile(id: uid, displayName: title)
                  : _profileForParticipant(p);
              return Tooltip(
                message: title,
                child: SelfAwareAvatar.tiny(
                  profile: profile,
                  size: _kVoterAvatarSize,
                ),
              );
            },
          ),
        if (overflow > 0)
          Container(
            width: _kVoterAvatarSize,
            height: _kVoterAvatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHigh,
              border: Border.all(color: cs.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$overflow',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
      ],
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

    final participantsByUserId = <String, BeaconParticipant>{
      for (final p in widget.participants) p.userId: p,
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

            // Poll controls stay out of the focus tree so they do not hold
            // primary focus after interaction. A focused Slider FocusNode can
            // leave the composer with a cursor but no soft keyboard on mobile.
            if (voted)
              ExcludeFocus(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...poll.variants.map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildVotedRow(
                          theme,
                          v,
                          showVoters,
                          participantsByUserId,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ExcludeFocus(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...poll.variants.map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: switch (poll.pollType) {
                          PollType.multiple => _buildMultipleUnvoted(
                            theme,
                            v.id,
                            v.description,
                          ),
                          PollType.range => _buildRangeUnvoted(
                            theme,
                            v.id,
                            v.description,
                          ),
                          _ => _buildSingleUnvoted(theme, v.id, v.description),
                        },
                      ),
                    ),
                    if (poll.pollType != PollType.single) ...[
                      const SizedBox(height: kSpacingSmall),
                      FilledButton(
                        onPressed: switch (poll.pollType) {
                          PollType.multiple when _pendingMultiple.isNotEmpty =>
                            () {
                              _submitVote(_pendingMultiple.toList());
                            },
                          PollType.range when _pendingRange.isNotEmpty => () {
                            final scored = _pendingRange.entries
                                .where((e) => e.value >= 1)
                                .toList();
                            if (scored.isEmpty) return;
                            for (final entry in scored) {
                              widget.onVote?.call(
                                [entry.key],
                                score: entry.value,
                              );
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
                  ],
                ),
              ),

            const SizedBox(height: kSpacingSmall),

            // Footer: vote count + revote button
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.beaconRoomPollVotesCount(poll.totalVotes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ),
                if (voted && poll.allowRevote && widget.onVote != null)
                  ExcludeFocus(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _revoting = true;
                        _pendingMultiple = poll.myVariantIds.toSet();
                        _pendingRange = {};
                      }),
                      child: const Text('Change answer'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
