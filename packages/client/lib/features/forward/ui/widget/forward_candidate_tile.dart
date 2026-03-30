import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

class ForwardCandidateTile extends StatelessWidget {
  const ForwardCandidateTile({
    required this.candidate,
    required this.isSelected,
    required this.onToggle,
    super.key,
  });

  final ForwardCandidate candidate;
  final bool isSelected;
  final VoidCallback? onToggle;

  String? _subtitle(L10n l10n) {
    if (candidate.involvement == CandidateInvolvement.declined) {
      return l10n.forwardDeclined;
    }
    if (candidate.involvement == CandidateInvolvement.author) {
      return l10n.forwardAuthor;
    }
    if (!candidate.isReachable) {
      return l10n.notReachable;
    }
    return switch (candidate.involvement) {
      CandidateInvolvement.forwarded => l10n.forwardAlreadyForwarded,
      CandidateInvolvement.committed => l10n.forwardCommitted,
      CandidateInvolvement.withdrawn => l10n.forwardWithdrawn,
      CandidateInvolvement.unseen => null,
      _ => null,
    };
  }

  Widget? _trailingIcon(ThemeData theme, L10n l10n) {
    if (candidate.canForwardTo) return null;
    if (candidate.involvement == CandidateInvolvement.declined) {
      return Icon(
        Icons.block,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    if (candidate.involvement == CandidateInvolvement.author) {
      return Icon(
        Icons.person,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    if (!candidate.isReachable) {
      return Icon(
        Icons.visibility_off,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    return Icon(
      switch (candidate.involvement) {
        CandidateInvolvement.committed => Icons.check_circle_outline,
        CandidateInvolvement.withdrawn => Icons.heart_broken,
        CandidateInvolvement.forwarded => Icons.forward_to_inbox,
        _ => Icons.info_outline,
      },
      size: 20,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final subtitleText = _subtitle(l10n);
    final canSelect = candidate.canForwardTo;
    return ListTile(
      enabled: canSelect,
      leading: AvatarRated(
        profile: candidate.profile,
      ),
      title: Text(
        candidate.title,
        style: canSelect
            ? null
            : theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
      subtitle: subtitleText == null
          ? null
          : Text(
              subtitleText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: canSelect
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onToggle?.call(),
            )
          : _trailingIcon(theme, l10n),
      onTap: canSelect ? onToggle : null,
    );
  }
}
