import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/inbox_provenance.dart';

Profile _senderProfile(InboxForwardSender s) => Profile(
  id: s.id,
  title: s.title,
  image: s.imageId != null && s.imageId!.isNotEmpty && s.imageId != 'null'
      ? ImageEntity(id: s.imageId!, authorId: s.id)
      : null,
);

/// Forwarders + “From …” line + optional coordination chip (flat; no inner card).
class InboxCardProvenanceRow extends StatelessWidget {
  const InboxCardProvenanceRow({
    required this.provenance,
    required this.coordinationStatus,
    super.key,
  });

  final InboxProvenance provenance;
  final BeaconCoordinationStatus coordinationStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final senders = provenance.senders;
    if (senders.isEmpty) return const SizedBox.shrink();

    final viewerId = context.watch<ProfileCubit>().state.profile.id;
    final primary = _senderProfile(senders.first);
    final primaryName = SelfUserHighlight.displayName(
      l10n,
      primary,
      viewerId,
    ).trim();

    final total = provenance.totalDistinctSenders;
    final fromLine = total > 1
        ? l10n.inboxFromForwarderPlus(
            primaryName,
            total - 1,
          )
        : l10n.inboxFromForwarder(primaryName);

    const maxAvatars = 3;
    final nShow = senders.length < maxAvatars ? senders.length : maxAvatars;
    final avatarProfiles = <Profile>[
      for (var i = 0; i < nShow; i++) _senderProfile(senders[i]),
    ];
    final overflowCount = provenance.totalDistinctSenders > nShow
        ? provenance.totalDistinctSenders - nShow
        : 0;

    final chip = switch (coordinationStatus) {
      BeaconCoordinationStatus.noCommitmentsYet => null,
      _ => BeaconCardPill(
        label: coordinationStatusLabel(l10n, coordinationStatus),
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    };

    return Row(
      children: [
        CompactForwarderAvatars(
          profiles: avatarProfiles,
          overflowCount: overflowCount,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            fromLine,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (chip != null) ...[
          const SizedBox(width: 6),
          chip,
        ],
      ],
    );
  }
}
