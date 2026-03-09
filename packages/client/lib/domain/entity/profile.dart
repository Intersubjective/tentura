import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';

import 'image_entity.dart';
import 'likable.dart';
import 'scorable.dart';

part 'profile.freezed.dart';

@freezed
abstract class Profile with _$Profile implements Likable, Scorable {
  const factory Profile({
    @Default('') String id,
    @Default('') String title,
    @Default('') String description,
    @Default(0) double rScore,
    @Default(0) double score,
    @Default(0) int myVote,
    ImageEntity? image,
  }) = _Profile;

  const Profile._();

  @override
  int get votes => myVote;

  @override
  double get reverseScore => rScore;

  bool get isEmpty => id.isEmpty;

  bool get isFriend => myVote > 0;

  bool get isNotFriend => !isFriend;

  bool get isSeeingMe => rScore > 0;

  bool get needEdit => id.isNotEmpty && title.isEmpty;

  bool get hasAvatar => image != null && image!.id.isNotEmpty;
  bool get hasNoAvatar => !hasAvatar;

  String get avatarUrl => hasAvatar
      ? '$kImageServer/$kImagesPath/$id/${image!.id}.$kImageExt'
      : kAvatarPlaceholderUrl;
}
