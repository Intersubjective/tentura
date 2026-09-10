import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final count = needsMe.length;

    final label = count == 1
        ? (needsMe.first.beacon?.title ?? '')
        : l10n.activityTriageRequestsNeedResponse(count);

    final profiles = _avatarProfiles(needsMe);
    final overflowCount = count > 3 ? count - 3 : 0;

    return Semantics(
      button: true,
      label: count == 1 ? label : l10n.activityTriageRequestsNeedResponse(count),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          key: TestIds.key(TestIds.activityTriageRow),
          borderRadius: BorderRadius.circular(tt.cardRadius),
          onTap: () => unawaited(context.router.push(const InboxTriageRoute())),
          child: SizedBox(
            height: tt.buttonHeight + tt.tightGap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.rowGap),
              child: Row(
                children: [
                  if (count > 1 && profiles.isNotEmpty) ...[
                    CompactForwarderAvatars(
                      profiles: profiles,
                      overflowCount: overflowCount,
                      sizeBucket: TenturaAvatarSize.small,
                    ),
                    SizedBox(width: tt.tightGap * 2),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.titleSmall(scheme.onSurface),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                    size: tt.iconSize,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
