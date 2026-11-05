import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';
import 'package:tentura/features/friends/domain/people_list_order.dart';
import 'package:tentura/features/friends/ui/people_new_subtitle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// Trusted-people rows in #912 order: optional «New» section, then by activity.
class PeopleOrderedList extends StatelessWidget {
  const PeopleOrderedList({
    required this.friends,
    required this.friendContexts,
    required this.listMeta,
    this.optimisticListMeta = const {},
    super.key,
  });

  final Map<String, Profile> friends;
  final Map<String, FriendContext> friendContexts;
  final Map<String, PersonListMeta> listMeta;
  final Map<String, PersonListMeta> optimisticListMeta;

  @override
  Widget build(BuildContext context) {
    final sections = buildPeopleListSections(
      friends: friends,
      listMeta: listMeta,
      optimisticNew: optimisticListMeta,
    );
    final mergedMeta = <String, PersonListMeta>{
      ...listMeta,
      for (final e in optimisticListMeta.entries)
        e.key: listMeta[e.key]?.mergedWith(e.value) ?? e.value,
    };

    return RelativeTimestampTicker(
      builder: (context) {
        final now = RelativeTimestampTicker.now();
        final l10n = L10n.of(context)!;
        final theme = Theme.of(context);
        final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
        final tt = context.tt;

        Widget personTile(Profile profile, {required bool inNewSection}) {
          final meta = mergedMeta[profile.id];
          String? trustOverride;
          String? interactionSuffix;
          if (inNewSection &&
              meta?.newSince != null &&
              meta!.newReason != null) {
            trustOverride = peopleNewSectionSubtitle(
              l10n: l10n,
              reason: meta.newReason!,
              newSince: meta.newSince!,
              now: now,
            );
          } else if (!inNewSection && meta?.lastInteractionAt != null) {
            interactionSuffix = compactRelativeTimeAgo(
              when: meta!.lastInteractionAt!,
              now: now,
              l10n: l10n,
            );
          }
          return NetworkPersonCard(
            key: ValueKey('people:${profile.id}:$inNewSection'),
            profile: profile,
            friendContext: friendContexts[profile.id] ?? FriendContext.empty,
            trustLineOverride: trustOverride,
            interactionTimeSuffix: interactionSuffix,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sections.newPeople.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.only(
                  top: tt.sectionGap,
                  bottom: tt.rowGap,
                ),
                child: Text(
                  l10n.friendsPeopleSectionNew,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
              ),
              for (var i = 0; i < sections.newPeople.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                personTile(sections.newPeople[i], inNewSection: true),
              ],
              if (sections.rest.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                  child: const Divider(height: 1),
                ),
            ],
            for (var i = 0; i < sections.rest.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              personTile(sections.rest[i], inNewSection: false),
            ],
          ],
        );
      },
    );
  }
}
