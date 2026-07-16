import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';
import 'attention_summary.dart';

part 'attention_feed.freezed.dart';

enum AttentionView { all, unread }

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
abstract class AttentionFeedSnapshot with _$AttentionFeedSnapshot {
  const factory AttentionFeedSnapshot({
    @Default(AttentionSummary()) AttentionSummary summary,
    @Default(<AttentionView, AttentionFeedPage>{})
    Map<AttentionView, AttentionFeedPage> pages,
    @Default(AttentionView.all) AttentionView activeView,
  }) = _AttentionFeedSnapshot;
}
