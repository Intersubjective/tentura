import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/request_access_reason.dart';

/// Informational line for observers whose access comes only from a related
/// (parent/child) request or the Post the Request grew from. Applied and
/// forwarded access are explained elsewhere, so they take priority and hide
/// this banner.
class RequestAccessReasonBanner extends StatelessWidget {
  const RequestAccessReasonBanner({
    required this.beacon,
    this.parent,
    this.parentPostExcerpt = '',
    super.key,
  });

  final Beacon beacon;

  /// The Request's hierarchy parent when it was read (#724): a Post parent
  /// is named, with a way to open it.
  final Beacon? parent;

  /// Root message excerpt for [parent] when it is a Post (#724).
  final String parentPostExcerpt;

  static const openParentKey = Key('request-access-reason-open-parent');

  @override
  Widget build(BuildContext context) {
    if (!requestAccessViaRelated(beacon)) return const SizedBox.shrink();

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final parent = this.parent;
    final post =
        parent != null &&
            parent.kind == BeaconKind.post &&
            parent.id != beacon.id &&
            requestAccessViaParent(beacon)
        ? parent
        : null;
    final postTitle = parentPostExcerpt.trim();
    final text = post == null
        ? l10n.requestAccessViaRelatedRequest
        : postTitle.isEmpty
        ? l10n.requestAccessViaParentPostUntitled
        : l10n.requestAccessViaParentPost(postTitle);

    return Padding(
      padding: EdgeInsets.only(bottom: tt.cardGap),
      child: TenturaTechCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: tt.iconSize,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                  ),
                  if (post != null)
                    TenturaTextAction(
                      key: openParentKey,
                      label: l10n.requestAccessOpenParentPost,
                      flushStart: true,
                      onPressed: () =>
                          context.router.push(BeaconViewRoute(id: post.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
