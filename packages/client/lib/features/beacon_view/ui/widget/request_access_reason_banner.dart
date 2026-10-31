import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/request_access_reason.dart';

const _postExcerptMaxLength = 40;
const _postExcerptEllipsis = '…';

/// Shortens a Post root excerpt for the access banner (#724): the sentence
/// wraps on phones; only the excerpt inside «…» is clipped (40 code units
/// keeps EN/RU copy within five lines at 375 px; ~60 overflowed RU).
String clipParentPostExcerptForAccessBanner(String excerpt) {
  final trimmed = excerpt.trim();
  if (trimmed.length <= _postExcerptMaxLength) return trimmed;
  const room = _postExcerptMaxLength - _postExcerptEllipsis.length;
  var head = _cutUtf16CodeUnits(trimmed, room);
  final space = head.lastIndexOf(RegExp(r'\s'));
  final atWordEnd =
      head.length < trimmed.length &&
      RegExp(r'\s').hasMatch(trimmed[head.length]);
  if (!atWordEnd && space > 0) head = head.substring(0, space);
  head = head.replaceFirst(RegExp(r'[\s\-–—,;:]+$'), '');
  if (head.isEmpty) head = _cutUtf16CodeUnits(trimmed, room);
  return '$head$_postExcerptEllipsis';
}

String _cutUtf16CodeUnits(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return s.substring(0, end);
}

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

  @visibleForTesting
  static const bodyTextKey = Key('request-access-reason-body');

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
    final postTitle = clipParentPostExcerptForAccessBanner(parentPostExcerpt);
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
                    key: bodyTextKey,
                    maxLines: 5,
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
