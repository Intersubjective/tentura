import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';

import 'coordinates.dart';
import 'image_entity.dart';
import 'likable.dart';
import 'polling.dart';
import 'profile.dart';
import 'scorable.dart';

part 'beacon.freezed.dart';

@freezed
abstract class Beacon with _$Beacon implements Likable, Scorable {
  const factory Beacon({
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String id,
    @Default('') String title,
    @Default('') String context,
    @Default('') String description,
    @Default(false) bool isPinned,
    @Default(false) bool isEnabled,
    @Default(0) double rScore,
    @Default(0) double score,
    @Default(0) int myVote,
    @Default(Profile()) Profile author,
    @Default({}) Set<String> tags,
    Coordinates? coordinates,
    ImageEntity? image,
    Polling? polling,
    DateTime? startAt,
    DateTime? endAt,
  }) = _Beacon;

  const Beacon._();

  @override
  int get votes => myVote;

  @override
  double get reverseScore => rScore;

  bool get hasPicture => image != null;
  bool get hasNoPicture => image == null;

  bool get hasPolling => polling != null;
  bool get hasNoPolling => polling == null;

  String get imageUrl => hasPicture
      ? '$kImageServer/$kImagesPath/${author.id}/${image!.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  static final empty = Beacon(
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
