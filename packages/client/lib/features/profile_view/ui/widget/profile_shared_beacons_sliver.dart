import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/profile_shared_beacons_cubit.dart';

class ProfileSharedBeaconsSliver extends StatelessWidget {
  const ProfileSharedBeaconsSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileSharedBeaconsCubit, ProfileSharedBeaconsState>(
      builder: (context, state) {
        if (state.isLoading && state.data == null) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingSmallT,
              child: LinearPiActive(),
            ),
          );
        }

        if (state.hasError || state.data == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final data = state.data!;
        final forwarded = data.forwarded;
        final coCommitted = data.coCommitted;

        if (forwarded.isEmpty && coCommitted.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final activeForwarded = forwarded
            .where((e) => e.beacon.lifecycle.isActiveSection)
            .toList();
        final archivedForwarded = forwarded
            .where((e) => !e.beacon.lifecycle.isActiveSection)
            .toList();

        final activeCoCommitted = coCommitted
            .where((e) => e.beacon.lifecycle.isActiveSection)
            .toList();
        final archivedCoCommitted = coCommitted
            .where((e) => !e.beacon.lifecycle.isActiveSection)
            .toList();

        final l10n = L10n.of(context)!;

        return SliverToBoxAdapter(
          child: Padding(
            padding: kPaddingAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (forwarded.isNotEmpty) ...[
                  _SectionHeader(label: l10n.profileSharedBeaconsForwardedSection),
                  for (final entry in [...activeForwarded, ...archivedForwarded])
                    _ForwardedBeaconCard(entry: entry),
                ],
                if (coCommitted.isNotEmpty) ...[
                  _SectionHeader(label: l10n.profileSharedBeaconsCoCommittedSection),
                  for (final entry in [...activeCoCommitted, ...archivedCoCommitted])
                    _CoCommittedBeaconCard(entry: entry),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: kSpacingMedium, bottom: kSpacingSmall),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ForwardedBeaconCard extends StatelessWidget {
  const _ForwardedBeaconCard({required this.entry});

  final ProfileForwardedBeaconEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: kPaddingSmallT,
      child: BeaconCardShell(
        muted: !entry.beacon.lifecycle.isActiveSection,
        onTap: () => context.read<ScreenCubit>().showBeacon(entry.beacon.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BeaconCardHeaderRow(
              beacon: entry.beacon,
              menu: const SizedBox.shrink(),
            ),
            const SizedBox(height: kSpacingSmall),
            _LifecyclePill(beacon: entry.beacon),
            if (entry.note.trim().isNotEmpty)
              _ForwardNote(note: entry.note.trim()),
            _ReactionRow(
              reaction: entry.reaction,
              rejectionMessage: entry.recipientRejectionMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoCommittedBeaconCard extends StatelessWidget {
  const _CoCommittedBeaconCard({required this.entry});

  final ProfileCoCommittedEntry entry;

  @override
  Widget build(BuildContext context) {
    final hasNote = entry.targetCommitMessage.trim().isNotEmpty;
    return Padding(
      padding: kPaddingSmallT,
      child: BeaconCardShell(
        muted: !entry.beacon.lifecycle.isActiveSection,
        onTap: () => context.read<ScreenCubit>().showBeacon(entry.beacon.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BeaconCardHeaderRow(
              beacon: entry.beacon,
              menu: const SizedBox.shrink(),
            ),
            const SizedBox(height: kSpacingSmall),
            _LifecyclePill(beacon: entry.beacon),
            if (hasNote) _ForwardNote(note: entry.targetCommitMessage.trim()),
            const _ReactionRow(
              reaction: TargetBeaconReaction.committed,
              rejectionMessage: '',
            ),
          ],
        ),
      ),
    );
  }
}

class _LifecyclePill extends StatelessWidget {
  const _LifecyclePill({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final isActive = beacon.lifecycle.isActiveSection;
    return Row(
      children: [
        BeaconCardPill(
          label: isActive ? l10n.beaconsFilterActive : l10n.beaconsFilterClosed,
          emphasized: isActive,
        ),
      ],
    );
  }
}

class _ForwardNote extends StatelessWidget {
  const _ForwardNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: kSpacingSmall),
      child: Text(
        note,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.reaction,
    required this.rejectionMessage,
  });

  final TargetBeaconReaction reaction;
  final String rejectionMessage;

  @override
  Widget build(BuildContext context) {
    if (reaction == TargetBeaconReaction.none) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String label, Color color) = switch (reaction) {
      TargetBeaconReaction.committed => (
        Icons.check_circle_outline,
        l10n.forwardReactionCommitted,
        scheme.tertiary,
      ),
      TargetBeaconReaction.onward => (
        Icons.forward_to_inbox,
        l10n.forwardReactionForwardedOnward,
        scheme.onSurfaceVariant,
      ),
      TargetBeaconReaction.watching => (
        Icons.visibility_outlined,
        l10n.forwardReactionWatching,
        scheme.onSurfaceVariant,
      ),
      TargetBeaconReaction.rejected => (
        Icons.block,
        rejectionMessage.trim().isNotEmpty
            ? l10n.myForwardDeclinedWithReason(rejectionMessage.trim())
            : l10n.myForwardDeclined,
        scheme.error,
      ),
      TargetBeaconReaction.none => throw StateError('unreachable'),
    };

    return Padding(
      padding: const EdgeInsets.only(top: kSpacingSmall),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
