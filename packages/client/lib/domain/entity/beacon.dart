import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/capability/capability_tag.dart';

import 'beacon_cover.dart';
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

    /// Capability slug driving symbol identity; null iff [needs] is empty.
    String? primaryNeedSlug,

    /// Author-selected cover image id; null when no image is attached.
    String? coverImageId,

    /// Author preference between photo and symbol presentation.
    @Default(BeaconCoverSource.photo) BeaconCoverSource coverSource,

    /// Lineage fork: immediate parent beacon id (nullable).
    String? lineageParentBeaconId,

    /// Lineage fork: root beacon id (nullable).
    String? lineageRootBeaconId,

    /// Hasura computed field: viewer may read beacon content (open / commit surfaces).
    @Default(true) bool canReadContent,
  }) = _Beacon;

  const Beacon._();

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

  /// Attached image matching [coverImageId]; null when absent or stale.
  ///
  /// Matching uses [ImageEntity.key] so an in-flight local selection resolves
  /// the same way a persisted server id does.
  ImageEntity? get coverImage {
    final selected = coverImageId;
    if (selected == null || selected.isEmpty) return null;
    for (final image in images) {
      if (image.key == selected) return image;
    }
    return null;
  }

  /// The only identity decision point. [allowPhoto] is false for image-error
  /// fallbacks so a broken photo degrades to symbol or neutral.
  BeaconIdentity resolveIdentity({required bool allowPhoto}) {
    if (!canReadContent) return const BeaconIdentityNeutral();

    if (allowPhoto && coverSource == BeaconCoverSource.photo) {
      final selected = coverImage;
      if (selected != null) return BeaconIdentityPhoto(selected);
    }

    final slug = primaryNeedSlug;
    if (slug != null && needs.contains(slug)) {
      final tag = CapabilityTag.fromSlug(slug);
      if (tag != null) return BeaconIdentitySymbol(tag);
    }
    return const BeaconIdentityNeutral();
  }

  BeaconIdentity get identity => resolveIdentity(allowPhoto: true);

  /// Gallery order: valid selected cover first, then persisted order.
  List<ImageEntity> get displayImages {
    final selected = coverImage;
    if (selected == null) return images;
    return [
      selected,
      for (final image in images)
        if (image.key != selected.key) image,
    ];
  }

  /// URLs aligned index-for-index with [displayImages].
  List<String> get displayImageUrls => [
    for (final img in displayImages) urlForImage(img),
  ];

  /// Image owner comes from the image itself when known, so an image can be
  /// addressed without a fully hydrated [author] (create/edit form previews).
  String urlForImage(ImageEntity image) {
    final owner = image.authorId.isNotEmpty ? image.authorId : author.id;
    return '$kImageServer/$kImagesPath/$owner/${image.id}.$kImageExt';
  }

  static final empty = Beacon(
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
