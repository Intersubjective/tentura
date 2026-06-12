import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';
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

  bool get isEmpty => id.isEmpty;

  bool get isFriend => myVote > 0;

  bool get isNotFriend => !isFriend;

  bool get isSeeingMe => rScore > 0;

  bool get needEdit => id.isNotEmpty && displayName.isEmpty;

  bool get hasAvatar => image != null && image!.id.isNotEmpty;
  bool get hasNoAvatar => !hasAvatar;

  String get avatarUrl => hasAvatar
      ? '$kImageServer/$kImagesPath/$id/${image!.id}.$kImageExt'
      : kAvatarPlaceholderUrl;
}
