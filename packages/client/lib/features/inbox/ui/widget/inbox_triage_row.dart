import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/inbox_item.dart';
import '../bloc/inbox_cubit.dart';

/// Fixed-height summary above the Activity feed (architecture §4.3).
class InboxTriageRow extends StatelessWidget {
  const InboxTriageRow({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<InboxCubit, InboxState, List<InboxItem>>(
      selector: (s) => s.needsMe,
      builder: (context, needsMe) {
        if (needsMe.isEmpty) {
          return const SizedBox.shrink();
        }
        return _InboxTriageRowBody(needsMe: needsMe);
      },
    );
  }
}

class _InboxTriageRowBody extends StatelessWidget {
  const _InboxTriageRowBody({required this.needsMe});

  final List<InboxItem> needsMe;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final count = needsMe.length;

    final label = count == 1
        ? (needsMe.first.beacon?.title ?? '')
        : l10n.activityTriageRequestsNeedResponse(count);

    final profiles = _avatarProfiles(needsMe);
    final overflowCount = count > 3 ? count - 3 : 0;

    return TenturaAttentionSummaryRow(
      label: label,
      maxLines: 1,
      semanticsLabel: count == 1
          ? label
          : l10n.activityTriageRequestsNeedResponse(count),
      inkWellKey: TestIds.key(TestIds.activityTriageRow),
      onTap: () => unawaited(context.router.push(const InboxTriageRoute())),
      leading: count > 1 && profiles.isNotEmpty
          ? CompactForwarderAvatars(
              profiles: profiles,
              overflowCount: overflowCount,
              sizeBucket: TenturaAvatarSize.small,
            )
          : null,
    );
  }
}

List<Profile> _avatarProfiles(List<InboxItem> needsMe) {
  const maxVisible = 3;
  final profiles = <Profile>[];
  for (final item in needsMe) {
    if (profiles.length >= maxVisible) break;
    final author = item.beacon?.author;
    if (author == null || author.id.isEmpty) continue;
    if (profiles.any((p) => p.id == author.id)) continue;
    profiles.add(author);
  }
  return profiles;
}
