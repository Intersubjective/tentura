import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';

import 'coordinates.dart';
import 'image_entity.dart';
import 'likable.dart';
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
    String? needSummary,
    String? successCriteria,
    @Default(false) bool isPinned,
    @Default(BeaconStatus.open) BeaconStatus status,
    DateTime? statusChangedAt,
    @Default(0) double rScore,
    @Default(0) double score,
    @Default(0) int myVote,
    @Default(Profile()) Profile author,
    @Default({}) Set<String> tags,
    @Default({}) Set<String> needs,
    @Default([]) List<ImageEntity> images,
    Coordinates? coordinates,
    String? addressLabel,
    DateTime? startAt,
    DateTime? endAt,

    /// From Hasura `beacon_review_window.closes_at` when tracked; null if no row.
    DateTime? reviewClosesAt,

    /// `beacon_review_window.status` (0=open, 1=complete); null if no row.
    int? reviewWindowStatus,

    /// Rows in `beacon_help_offer` for this beacon (from GraphQL aggregate when fetched).
    @Default(0) int helpOfferCount,

    /// Active help offers with no author coordination response (list fetch aggregate).
    @Default(0) int unansweredHelpOfferCount,

    /// Active help-offer user profiles when `help_offers` relation is fetched (My Work).
    @Default([]) List<Profile> helpOfferUsers,

    /// Curated symbolic icon key (client catalog); null = default identity tile.
    String? iconCode,

    /// ARGB background from constrained palette; null if unset.
    int? iconBackground,

    /// Lineage fork: immediate parent beacon id (nullable).
    String? lineageParentBeaconId,

    /// Lineage fork: root beacon id (nullable).
    String? lineageRootBeaconId,

    /// Hasura computed field: viewer may read beacon content (open / commit surfaces).
    @Default(true) bool canReadContent,
  }) = _Beacon;

  const Beacon._();

  /// True when [needSummary] is a non-empty trimmed string (post–need-first schema).
  bool get hasNeedSummary => needSummary?.trim().isNotEmpty ?? false;

  /// Non-closed listing (open-family, DRAFT, WRAPPING UP); profile filters and author controls.
  bool get isListed => status.isActiveSection;

  /// Viewer may open this beacon (matches server `beacon_can_read_content`).
  bool get canOpenAsViewer => canReadContent;

  /// Viewer may commit (offer help) when readable and beacon is open-family.
  bool get canCommitAsViewer => canReadContent && status.isOpenFamily;

  /// Non-author may offer help only when status is open-family (matches server).
  bool get allowsNewHelpOfferAsNonAuthor => status.isOpenFamily;

  /// Help offerer may withdraw in open-family or WRAPPING UP.
  bool get allowsWithdrawWhileHelpOffered => status.allowsCoordination;

  bool get allowsCoordination => status.allowsCoordination;

  bool get allowsForward => status.allowsForward;

  bool get isFinished => status.isFinished;

  @override
  int get votes => myVote;

  @override
  double get reverseScore => rScore;

  bool get hasPicture => images.isNotEmpty;
  bool get hasNoPicture => images.isEmpty;

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
