import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';

import 'beacon_lifecycle.dart';
import 'coordination_status.dart';
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
    @Default(BeaconLifecycle.open) BeaconLifecycle lifecycle,
    @Default(0) double rScore,
    @Default(0) double score,
    @Default(0) int myVote,
    @Default(Profile()) Profile author,
    @Default({}) Set<String> tags,
    @Default([]) List<ImageEntity> images,
    Coordinates? coordinates,
    Polling? polling,
    DateTime? startAt,
    DateTime? endAt,

    /// From Hasura `beacon_review_window.closes_at` when tracked; null if no row.
    DateTime? reviewClosesAt,

    /// `beacon_review_window.status` (0=open, 1=complete); null if no row.
    int? reviewWindowStatus,
    @Default(BeaconCoordinationStatus.noCommitmentsYet)
    BeaconCoordinationStatus coordinationStatus,
    DateTime? coordinationStatusUpdatedAt,

    /// Rows in `beacon_commitment` for this beacon (from GraphQL aggregate when fetched).
    @Default(0) int commitmentCount,

    /// Curated symbolic icon key (client catalog); null = default identity tile.
    String? iconCode,

    /// ARGB background from constrained palette; null if unset.
    int? iconBackground,
  }) = _Beacon;

  const Beacon._();

  /// Non-closed listing (OPEN, DRAFT, PENDING_REVIEW, CLOSED_REVIEW_OPEN); profile filters and author controls.
  bool get isListed => lifecycle.isActiveSection;

  /// Non-author may start a commitment only when lifecycle is OPEN (matches server `beaconCommit`).
  bool get allowsNewCommitAsNonAuthor => lifecycle == BeaconLifecycle.open;

  /// Committer may withdraw in OPEN, PENDING_REVIEW, or CLOSED_REVIEW_OPEN (matches server `beaconWithdraw`).
  bool get allowsWithdrawWhileCommitted =>
      lifecycle == BeaconLifecycle.open ||
      lifecycle == BeaconLifecycle.pendingReview ||
      lifecycle == BeaconLifecycle.closedReviewOpen;

  @override
  int get votes => myVote;

  @override
  double get reverseScore => rScore;

  bool get hasPicture => images.isNotEmpty;
  bool get hasNoPicture => images.isEmpty;

  bool get hasPolling => polling != null;
  bool get hasNoPolling => polling == null;

  /// Author chose a curated icon key for the identity tile.
  bool get hasIdentityTile => iconCode != null && iconCode!.isNotEmpty;

  /// URL for the first (thumbnail) image.
  String get imageUrl => hasPicture
      ? '$kImageServer/$kImagesPath/${author.id}/${images.first.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  /// URLs for all images in gallery order.
  List<String> get imageUrls => [
    for (final img in images)
      '$kImageServer/$kImagesPath/${author.id}/${img.id}.$kImageExt',
  ];

  static final empty = Beacon(
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
