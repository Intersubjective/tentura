import 'package:tentura_server/domain/entity/notification_kind.dart';

class BeaconNotificationBatchAggregator {
  const BeaconNotificationBatchAggregator();

  /// Builds coalesced title/body when [count] > 1 for same receiver+beacon+band.
  ({String title, String body}) aggregate({
    required int count,
    required NotificationKind dominantKind,
    required String latestTitle,
    required String latestBody,
    required String? beaconTitle,
    required Map<NotificationKind, int> kindCounts,
  }) {
    if (count <= 1) {
      return (title: latestTitle, body: latestBody);
    }

    final title = beaconTitle != null && beaconTitle.trim().isNotEmpty
        ? beaconTitle.trim()
        : latestTitle;

    if (kindCounts.length == 1) {
      final kind = kindCounts.keys.first;
      final n = kindCounts[kind]!;
      return (
        title: title,
        body: _pluralBody(kind, n, latestBody),
      );
    }

  final actionable = kindCounts.keys.where(_isActionable).toList();
    if (actionable.length == 1 && kindCounts[actionable.first]! < count) {
      final n = count;
      final suffix = latestBody.isNotEmpty ? ', including: $latestBody' : '';
      return (
        title: title,
        body: '$n coordination updates$suffix',
      );
    }

    return (
      title: title,
      body: '$count coordination updates',
    );
  }

  String _pluralBody(NotificationKind kind, int n, String latestBody) {
    final suffix = latestBody.isNotEmpty ? ', including: $latestBody' : '';
    return switch (kind) {
      NotificationKind.needsMe => '$n items need you$suffix',
      NotificationKind.promiseMade => '$n new promises$suffix',
      NotificationKind.coordinationChanged => '$n coordination updates$suffix',
      NotificationKind.blockerOpened => '$n blockers opened$suffix',
      NotificationKind.blockerResolved => '$n blockers resolved$suffix',
      NotificationKind.newRelay => '$n beacons forwarded to you$suffix',
      NotificationKind.commitmentEvent => '$n commitment updates$suffix',
      NotificationKind.reviewReady => '$n beacons ready to review$suffix',
      _ => '$n beacon updates$suffix',
    };
  }

  bool _isActionable(NotificationKind kind) => switch (kind) {
        NotificationKind.needsMe ||
        NotificationKind.blockerOpened ||
        NotificationKind.reviewReady =>
          true,
        _ => false,
      };

  NotificationKind pickDominantKind(Map<NotificationKind, int> kindCounts) {
    NotificationKind? best;
    var bestScore = -1;
    for (final entry in kindCounts.entries) {
      final score = entry.value + (_isActionable(entry.key) ? 1000 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return best ?? NotificationKind.coordinationChanged;
  }
}
