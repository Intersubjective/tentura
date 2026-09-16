import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';
import 'attention_summary.dart';

part 'attention_feed.freezed.dart';

enum AttentionView { all, unread, needsYou }

enum AttentionSurface {
  myWork,
  activity;

  static const myWorkWire = 'myWork';
  static const activityWire = 'activity';

  String get wireName => switch (this) {
    AttentionSurface.myWork => myWorkWire,
    AttentionSurface.activity => activityWire,
  };

  static AttentionSurface fromWire(String wire) {
    switch (wire) {
      case myWorkWire:
        return AttentionSurface.myWork;
      case activityWire:
        return AttentionSurface.activity;
      default:
        return AttentionSurface.activity;
    }
  }
}

enum AttentionItemKind {
  receipt,
  forward,
  watchingDigest,
  requestActivity;

  static const receiptWire = 'receipt';
  static const forwardWire = 'forward';
  static const watchingDigestWire = 'watchingDigest';
  static const requestActivityWire = 'requestActivity';

  String get wireName => switch (this) {
    AttentionItemKind.receipt => receiptWire,
    AttentionItemKind.forward => forwardWire,
    AttentionItemKind.watchingDigest => watchingDigestWire,
    AttentionItemKind.requestActivity => requestActivityWire,
  };

  static AttentionItemKind fromWire(String wire) {
    switch (wire) {
      case receiptWire:
        return AttentionItemKind.receipt;
      case forwardWire:
        return AttentionItemKind.forward;
      case watchingDigestWire:
        return AttentionItemKind.watchingDigest;
      case requestActivityWire:
        return AttentionItemKind.requestActivity;
      default:
        return AttentionItemKind.receipt;
    }
  }
}

/// Stable ids for independently mounted feed destinations (Activity, My Work, …).
abstract final class AttentionFeedDestinationId {
  static const activityStream = 'activity_stream';
  static const history = 'notification_history';
}

/// Repository surface filter for a mounted feed destination.
///
/// Unknown destination ids use unscoped fetches (`null`) until registered here.
AttentionSurface? surfaceForDestination(String destinationId) {
  switch (destinationId) {
    case AttentionFeedDestinationId.activityStream:
      return AttentionSurface.activity;
    case AttentionFeedDestinationId.history:
      return null;
    default:
      return null;
  }
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
