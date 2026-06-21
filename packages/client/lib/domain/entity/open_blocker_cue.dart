import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/domain/entity/coordination_item.dart' show CoordinationItem;

import 'profile.dart';

part 'open_blocker_cue.freezed.dart';

/// Open coordination blocker surfaced on cards / HUD (domain boundary).
@freezed
abstract class OpenBlockerCue with _$OpenBlockerCue {
  const factory OpenBlockerCue({
    required String creatorId,
    required DateTime raisedAt, @Default('') String targetPersonId,
    @Default('') String responsibleUserId,
    @Default('') String title,
    Profile? raiser,
  }) = _OpenBlockerCue;

  const OpenBlockerCue._();

  /// Matches [CoordinationItem.responsibleUserId] for blockers.
  static String resolveResponsibleUserId({
    required String creatorId,
    String? targetPersonId,
  }) {
    final target = targetPersonId?.trim() ?? '';
    if (target.isNotEmpty) return target;
    return creatorId;
  }

  bool isResponsible(String viewerUserId) =>
      responsibleUserId == viewerUserId;
}
