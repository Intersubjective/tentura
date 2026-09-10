import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';
import 'attention_summary.dart';

part 'attention_feed.freezed.dart';

enum AttentionView { all, unread, needsYou }

/// Stable ids for independently mounted feed destinations (Activity, My Work, …).
abstract final class AttentionFeedDestinationId {
  static const activity = 'activity_feed';
  static const myWorkObligations = 'my_work_obligations_feed';
}

@freezed
abstract class AttentionFeedPage with _$AttentionFeedPage {
  const factory AttentionFeedPage({
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> items,
    String? nextCursor,
  }) = _AttentionFeedPage;
}

@freezed
abstract class AttentionFeed with _$AttentionFeed {
  const factory AttentionFeed({
    required AttentionSummary summary,
    required AttentionFeedPage page,
  }) = _AttentionFeed;
}

@freezed
abstract class AttentionFeedSession with _$AttentionFeedSession {
  const factory AttentionFeedSession({
    @Default(AttentionView.all) AttentionView activeView,
    @Default('') String searchText,
    @Default(<AttentionView, AttentionFeedPage>{})
    Map<AttentionView, AttentionFeedPage> pages,
    @Default(0) int requestGeneration,
    Object? headRefreshError,
  }) = _AttentionFeedSession;

  const AttentionFeedSession._();

  String? get normalizedSearch {
    final trimmed = searchText.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

@freezed
abstract class AttentionFeedSnapshot with _$AttentionFeedSnapshot {
  const factory AttentionFeedSnapshot({
    @Default(AttentionSummary()) AttentionSummary summary,
  }) = _AttentionFeedSnapshot;
}
