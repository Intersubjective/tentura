import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura_root/domain/enums.dart';

import 'image_entity.dart';
import 'likable.dart';
import 'scorable.dart';

part 'profile.freezed.dart';

@freezed
abstract class Profile with _$Profile implements Likable, Scorable {
  const factory Profile({
    @Default('') String id,
    @Default('') String displayName,

    /// Subjective profiles: the viewer's private name for this user (from
    /// their contact map), empty when none. Render via [shownName];
    /// [displayName] stays the user's objective self-chosen name.
    @Default('') String contactName,

    /// Public @mention handle (5–30 `[a-z0-9_]`, optional).
    @Default('') String handle,
    @Default('') String description,
    @Default(0) double rScore,
    @Default(0) double score,
    @Default(0) int myVote,
    @Default(false) bool subjectExplicitlyTrustsViewer,
    @Default(false) bool isMutualFriend,
    ImageEntity? image,
    UserPresenceStatus? presenceStatus,
    DateTime? presenceLastSeenAt,
  }) = _Profile;

  const Profile._();

  @override
  int get votes => myVote;

  @override
  double get reverseScore => rScore;

  /// What the viewer should see: their own contact name when set,
  /// the user's self-chosen display name otherwise.
  String get shownName => contactName.isNotEmpty ? contactName : displayName;

  /// User-facing label: [shownName] → @handle → [unknownPersonLabel].
  /// Never returns [id].
  String displayLabel(String unknownPersonLabel) {
    final name = shownName.trim();
    if (name.isNotEmpty) return name;
    final h = handle.trim();
    if (h.isNotEmpty) return '@$h';
    return unknownPersonLabel;
  }

  bool get isEmpty => id.isEmpty;

  bool get isFriend => myVote > 0;

  bool get isNotFriend => !isFriend;

  bool get viewerExplicitlyTrustsSubject => myVote > 0;

  bool get forwardMeritRankPositive => score > 0;

  bool get reverseMeritRankPositive => rScore > 0;

  bool get viewerCanSeeSubject =>
      viewerExplicitlyTrustsSubject || forwardMeritRankPositive;

  bool get subjectCanSeeViewer =>
      subjectExplicitlyTrustsViewer || reverseMeritRankPositive;

  /// Two-way visibility: each direction is explicit trust or positive MeritRank.
  /// Drives the open/closed eye badge and forward reachability.
  bool get isMutuallyVisible => viewerCanSeeSubject && subjectCanSeeViewer;

  /// Reverse MeritRank only — not incoming explicit trust.
  bool get isSeeingMe => reverseMeritRankPositive;

  bool get needEdit => id.isNotEmpty && displayName.isEmpty;

  /// True when the viewer should be nudged to set a real display name.
  bool get needsDisplayNamePrompt =>
      id.isNotEmpty && needsDisplayNamePromptFor(displayName);

  bool get hasAvatar => image != null && image!.id.isNotEmpty;
  bool get hasNoAvatar => !hasAvatar;

  String get avatarUrl => hasAvatar
      ? '$kImageServer/$kImagesPath/$id/${image!.id}.$kImageExt'
      : kAvatarPlaceholderUrl;
}
