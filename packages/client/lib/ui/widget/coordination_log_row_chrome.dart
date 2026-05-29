import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Log tab row — avatar diameter.
const kCoordinationLogAvatarSize = 20.0;

/// Log tab row — semantic event icon size.
const kCoordinationLogEventIconSize = 22.0;

Profile profileFromBeaconParticipant(BeaconParticipant p) => Profile(
      id: p.userId,
      displayName: p.userTitle,
      image: p.userHasPicture
          ? ImageEntity(
              id: p.userImageId,
              authorId: p.userId,
              blurHash: p.userBlurHash,
              height: p.userPicHeight,
              width: p.userPicWidth,
            )
          : null,
    );

Widget coordinationLogParticipantAvatar(BeaconParticipant participant) =>
    ClipOval(
      child: AvatarRated(
        profile: profileFromBeaconParticipant(participant),
        size: kCoordinationLogAvatarSize,
        withRating: false,
      ),
    );

/// Log tab leading segment: `[src avatar] [icon] [dst avatar?]`.
Widget coordinationLogTabLeadRow({
  required Widget eventIcon,
  BeaconParticipant? actor,
  BeaconParticipant? target,
}) {
  if (actor == null) return eventIcon;

  final children = <Widget>[
    coordinationLogParticipantAvatar(actor),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: eventIcon,
    ),
  ];

  if (target != null) {
    children.add(coordinationLogParticipantAvatar(target));
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

/// Body snippet for log rows: `diffJson.body` / `diffJson.title`, then linked
/// coordination item preview, else [fallback].
String coordinationLogEventBodySnippet({
  required BeaconActivityEvent event,
  required String fallback,
  Map<String, String> itemContentById = const {},
}) {
  final fromDiff = _bodyFromDiffJson(event.diffJson);
  if (fromDiff != null && fromDiff.isNotEmpty) return fromDiff;

  final itemId = resolveCoordinationItemIdForEvent(
    event,
    itemContentById: itemContentById,
  );
  if (itemId != null) {
    final fromItem = itemContentById[itemId]?.trim();
    if (fromItem != null && fromItem.isNotEmpty) return fromItem;
  }

  return fallback;
}

/// Resolve coordination item id from the event field or loaded item metadata.
String? resolveCoordinationItemIdForEvent(
  BeaconActivityEvent event, {
  Map<String, String> itemContentById = const {},
  Iterable<CoordinationItem> items = const [],
}) {
  final direct = event.coordinationItemId?.trim();
  if (direct != null && direct.isNotEmpty) return direct;

  if (itemContentById.isNotEmpty) {
    final msgId = event.sourceMessageId?.trim();
    if (msgId != null && msgId.isNotEmpty) {
      for (final item in items) {
        if (item.id.isEmpty) continue;
        if (!itemContentById.containsKey(item.id)) continue;
        final linked = item.linkedMessageId?.trim();
        if (linked != null && linked == msgId) return item.id;
        final anchor = item.threadAnchorMessageId;
        if (anchor != null && anchor == msgId) return item.id;
      }
    }
  }

  return null;
}

/// `itemId` → primary text preview for Log row enrichment.
Map<String, String> coordinationItemContentLookup(Iterable<CoordinationItem> items) {
  return {
    for (final item in items)
      if (item.id.isNotEmpty)
        item.id: item.contentPreview,
  };
}

/// All coordination items from the Items tab cubit state.
Iterable<CoordinationItem> coordinationItemsFromTabState({
  required Iterable<CoordinationItem> openItems,
  required Iterable<CoordinationItem> closedItems,
  required Iterable<CoordinationItem> draftAskItems,
  required Iterable<CoordinationItem> draftPromiseItems,
  required Iterable<CoordinationItem> draftBlockerItems,
  CoordinationItem? currentCoordinationPlan,
}) sync* {
  yield* openItems;
  yield* closedItems;
  yield* draftAskItems;
  yield* draftPromiseItems;
  yield* draftBlockerItems;
  if (currentCoordinationPlan != null) {
    yield currentCoordinationPlan;
  }
}

String? _bodyFromDiffJson(String? diffJson) {
  if (diffJson == null || diffJson.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(diffJson);
    if (decoded is! Map) return null;
    final body = decoded['body'];
    if (body is String && body.trim().isNotEmpty) return body.trim();
    final title = decoded['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();
  } on Object {
    return null;
  }
  return null;
}

String coordinationLogTimestampLabel(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}
