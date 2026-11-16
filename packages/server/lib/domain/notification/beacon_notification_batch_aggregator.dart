import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_text.dart';

class BeaconNotificationBatchAggregator {
  const BeaconNotificationBatchAggregator();

  /// Localized coalesced push (spec §5.1): the Request label stays the title
  /// (`Tentura` when the recipient cannot read it); the body counts updates
  /// and quotes the latest sentence. One dominant actionable kind leads with
  /// its own phrase.
  ({String title, String body}) collapsed({
    required int count,
    required String locale,
    required String? entityLabel,
    required String? latestSentence,
    required Map<NotificationKind, int> kindCounts,
    BeaconKind beaconKind = BeaconKind.request,
  }) {
    final ru = locale.startsWith('ru');
    final label = entityLabel?.trim() ?? '';
    if (!ru && kindCounts.length == 1) {
      // One kind, English: its own phrase («2 replies to your posts»).
      return (
        title: label.isEmpty ? 'Tentura' : label,
        body: _pluralBody(
          kindCounts.keys.first,
          count,
          latestSentence ?? '',
          beaconKind,
        ),
      );
    }
    final actionable = kindCounts.keys.where(_isActionable).toList();
    final phrase = actionable.length == 1 && kindCounts.length > 1
        ? _actionablePhrase(actionable.first, count, ru)
        : kindCounts.length == 1 && _isActionable(kindCounts.keys.first)
        ? _actionablePhrase(kindCounts.keys.first, count, ru)
        : null;
    final counted =
        phrase ??
        '$count ${NotificationText.plural(count, locale, one: ru ? 'обновление' : 'update', few: 'обновления', many: ru ? 'обновлений' : 'updates')}';
    final sentence = latestSentence ?? '';
    final tail = label.isEmpty || sentence.isEmpty
        ? ''
        : ' · ${ru ? 'последнее' : 'latest'}: $sentence';
    return (title: label.isEmpty ? 'Tentura' : label, body: '$counted$tail');
  }

  String _actionablePhrase(NotificationKind kind, int n, bool ru) =>
      switch (kind) {
        NotificationKind.needsMe =>
          ru ? '$n — нужен ваш ответ' : '$n items need you',
        NotificationKind.staleRemind =>
          ru ? '$n — требуют внимания' : '$n items need attention',
        NotificationKind.blockerOpened =>
          ru ? '$n — открыты блокеры' : '$n blockers opened',
        NotificationKind.reviewReady =>
          ru ? '$n — готовы к проверке' : '$n requests ready to review',
        NotificationKind.roomMention =>
          ru ? '$n — упоминания вас' : '$n mentions of you',
        _ => '$n',
      };

  String _pluralBody(
    NotificationKind kind,
    int n,
    String latestBody,
    BeaconKind beaconKind,
  ) {
    final suffix = latestBody.isNotEmpty ? ', including: $latestBody' : '';
    final isPost = beaconKind == BeaconKind.post;
    return switch (kind) {
      NotificationKind.newRelay when isPost =>
        '$n posts shared with you$suffix',
      NotificationKind.postExpiringSoon => '$n posts are about to expire',
      NotificationKind.postFirstResponse => '$n replies to your posts$suffix',
      NotificationKind.needsMe => '$n items need you$suffix',
      NotificationKind.promiseMade => '$n new promises$suffix',
      NotificationKind.coordinationChanged => '$n coordination updates$suffix',
      NotificationKind.blockerOpened => '$n blockers opened$suffix',
      NotificationKind.blockerResolved => '$n blockers resolved$suffix',
      NotificationKind.newRelay => '$n requests forwarded to you$suffix',
      NotificationKind.commitmentEvent => '$n commitment updates$suffix',
      NotificationKind.commitmentDeclined => '$n declined offers$suffix',
      NotificationKind.commitmentRemoved => '$n discussion removals$suffix',
      NotificationKind.commitmentReleased => '$n participation endings$suffix',
      NotificationKind.reviewReady => '$n requests ready to review$suffix',
      NotificationKind.staleRemind => '$n items need attention$suffix',
      NotificationKind.roomMention => '$n mentions of you$suffix',
      _ => '$n ${isPost ? 'post' : 'request'} updates$suffix',
    };
  }

  bool _isActionable(NotificationKind kind) => switch (kind) {
    NotificationKind.needsMe ||
    NotificationKind.staleRemind ||
    NotificationKind.blockerOpened ||
    NotificationKind.reviewReady ||
    NotificationKind.roomMention => true,
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
