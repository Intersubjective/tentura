import 'dart:convert';

import 'package:tentura/features/forward/domain/entity/help_path_node.dart';
import 'package:tentura/features/notification_settings/domain/entity/notification_settings.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Two-line Updates copy for a forward-helped receipt.
class ForwardHelpedFeedRowCopy {
  const ForwardHelpedFeedRowCopy({
    required this.headline,
    required this.body,
  });

  final String headline;
  final String body;
}

/// Parsed `forwardHelped` presentation payload (#774).
class ForwardHelpedPresentation {
  const ForwardHelpedPresentation({
    required this.beaconTitle,
    required this.helperId,
    required this.authorId,
    required this.path,
    required this.done,
  });

  final String beaconTitle;
  final String? helperId;
  final String? authorId;
  final List<HelpPathNode> path;
  final bool done;
}

bool isForwardHelpedPresentationKey(String? presentationKey) =>
    presentationKey == 'forward_helped';

ForwardHelpedPresentation? forwardHelpedFromPresentationPayload(
  String presentationPayloadJson,
) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty) return null;
  final Object? decoded = jsonDecode(trimmed);
  if (decoded is! Map<String, Object?>) return null;
  if (decoded['eventType'] != 'forwardHelped') return null;
  final nodes = decoded['path'];
  if (nodes is! List<Object?>) return null;
  final path = <HelpPathNode>[];
  for (final node in nodes) {
    if (node is! Map<String, Object?>) return null;
    if (node['anonymousCount'] case final int count when count > 0) {
      path.add(HelpPathNode.anonymous(count));
      continue;
    }
    if (node['userId'] case final String id) {
      final name = node['displayName'];
      if (name is! String || name.isEmpty) return null;
      path.add(HelpPathNode.named(userId: id, displayName: name));
      continue;
    }
    return null;
  }
  final done = decoded['done'] == true;
  return ForwardHelpedPresentation(
    beaconTitle: switch (decoded['beaconTitle']) {
      final String title => title,
      _ => '',
    },
    helperId: switch (decoded['helperId']) {
      final String id => id,
      _ => null,
    },
    authorId: switch (decoded['authorId']) {
      final String id => id,
      _ => null,
    },
    path: path,
    done: done,
  );
}

String forwardHelpedPathLabel({
  required List<HelpPathNode> path,
  required String? viewerUserId,
  required L10n l10n,
}) {
  final parts = <String>[];
  for (final node in path) {
    if (node.isAnonymous) {
      parts.add(l10n.helpPathAnonymousCount(node.anonymousCount));
    } else if (viewerUserId != null && node.userId == viewerUserId) {
      parts.add(l10n.updatesForwardHelpedYou);
    } else {
      parts.add(node.displayName ?? '');
    }
  }
  return parts.where((part) => part.isNotEmpty).join(' → ');
}

String? _displayNameOnPath(List<HelpPathNode> path, String? userId) {
  if (userId == null) return null;
  for (final node in path) {
    if (node.userId == userId) return node.displayName;
  }
  return null;
}

ForwardHelpedFeedRowCopy? forwardHelpedReceiptDisplayCopy({
  required String receiptTitle,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  required int collapsedCount,
  String? viewerUserId,
}) {
  if (!isForwardHelpedPresentationKey(presentationKey)) return null;
  final content = forwardHelpedFromPresentationPayload(presentationPayloadJson);
  if (content == null) return null;

  final pathLabel = forwardHelpedPathLabel(
    path: content.path,
    viewerUserId: viewerUserId,
    l10n: l10n,
  );
  final authorName = _displayNameOnPath(content.path, content.authorId);
  final helperName = _displayNameOnPath(content.path, content.helperId);
  final title = content.beaconTitle;

  final headline = _forwardHelpedHeadline(
    l10n: l10n,
    collapsedCount: collapsedCount,
    done: content.done,
    receiptTitle: receiptTitle.trim(),
  );

  final body = content.done
      ? _joinPathAndSentence(
          pathLabel,
          l10n.updatesForwardHelpedDoneBody(
            title,
            helperName ?? l10n.updatesForwardHelpedHelperFallback,
          ),
        )
      : l10n.updatesForwardHelpedAcceptedBody(
          pathLabel,
          title,
          authorName ?? l10n.updatesForwardHelpedAuthorFallback,
        );

  return ForwardHelpedFeedRowCopy(headline: headline, body: body);
}

String _forwardHelpedHeadline({
  required L10n l10n,
  required int collapsedCount,
  required bool done,
  required String receiptTitle,
}) {
  final base = collapsedCount > 1
      ? l10n.updatesForwardHelpedTitlePlural(collapsedCount)
      : l10n.updatesForwardHelpedTitle;
  if (done) {
    return '${l10n.updatesForwardHelpedSparkle}$base · ${l10n.updatesForwardHelpedDoneMark}';
  }
  if (receiptTitle.contains('Done ✓') || receiptTitle.contains('Done')) {
    return '${l10n.updatesForwardHelpedSparkle}$receiptTitle';
  }
  return '${l10n.updatesForwardHelpedSparkle}$base';
}

String _joinPathAndSentence(String pathLabel, String sentence) {
  if (pathLabel.isEmpty) return sentence;
  return '$pathLabel · $sentence';
}

/// Maps a forward-helped receipt category wire name to settings, when known.
NotificationSettingsCategory? forwardHelpedNotificationSettingsCategory(
  String categoryWire,
) {
  // Server uses [NotificationCategory.coordination] today; a dedicated
  // «Your forwards» category would add a matching enum value on both sides.
  return NotificationSettings.categoryFromName(categoryWire);
}
