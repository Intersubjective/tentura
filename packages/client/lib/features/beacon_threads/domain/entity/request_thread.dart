import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

part 'request_thread.freezed.dart';

enum RequestThreadKind { general, ask, promise, blocker }

abstract final class ThreadMessagePreviewKind {
  static const text = 0;
  static const attachment = 1;
  static const planUpdated = 2;
  static const factPinned = 3;
  static const participantStatus = 4;
  static const coordination = 5;
  static const needInfo = 6;
  static const done = 7;
  static const poll = 8;
  static const join = 9;
  static const values = <int>{0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
}

@freezed
abstract class ThreadMessagePreview with _$ThreadMessagePreview {
  const factory ThreadMessagePreview({
    required int kind,
    String? excerpt,
    @Default(false) bool hasAttachment,
    String? joinedUserId,
    String? admissionReason,
    String? linkedItemId,
    int? linkedEventKind,
    int? itemKind,
    String? itemTitle,
    String? pollTitle,
    String? factTitle,
    int? factVisibility,
  }) = _ThreadMessagePreview;
}

@freezed
abstract class RequestThread with _$RequestThread {
  static const generalId = 'general';

  const factory RequestThread({
    required String threadId,
    required RequestThreadKind kind,
    @Default(0) int unreadCount,
    @Default(0) int messageCount,
    DateTime? lastSeenAt,
    DateTime? lastMessageAt,
    String? lastMessageAuthorId,
    ThreadMessagePreview? lastMessagePreview,
    CoordinationItem? item,
  }) = _RequestThread;

  const RequestThread._();

  bool get isGeneral => item == null;

  bool get isDraft => item?.published == false;

  bool get isActive => item?.isActive ?? true;
}
