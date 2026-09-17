import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_cover.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Typed list-card preview — not an action-capable [Beacon].
class BeaconRequestPreviewData {
  const BeaconRequestPreviewData({
    required this.beaconId,
    required this.title,
    required this.status,
    required this.phaseStatus,
    required this.coverSource,
    required this.needs,
    this.author,
    this.admittedHelpers = const [],
    this.admittedHelperCount = 0,
    this.description,
    this.coverImageId,
    this.coverThumbImageId,
    this.primaryNeedSlug,
  });

  final String beaconId;
  final String title;
  final Profile? author;
  final List<Profile> admittedHelpers;
  final int admittedHelperCount;
  final BeaconStatus status;
  final BeaconPhaseStatusPresentation phaseStatus;
  final String? description;
  final BeaconCoverSource coverSource;
  final String? coverImageId;
  final String? coverThumbImageId;
  final String? primaryNeedSlug;
  final Set<String> needs;

  factory BeaconRequestPreviewData.fromHierarchySummary(
    L10n l10n,
    BeaconHierarchySummary summary, {
    required DateTime now,
  }) {
    final owner = summary.owner;
    return BeaconRequestPreviewData(
      beaconId: summary.beaconId,
      title: summary.title?.trim().isNotEmpty == true
          ? summary.title!.trim()
          : l10n.beaconUntitled,
      author: owner == null
          ? null
          : Profile(
              id: owner.id,
              displayName: owner.displayName,
              image: _avatarImage(owner),
            ),
      admittedHelpers: [
        for (final h in summary.admittedHelperPreviews)
          Profile(
            id: h.id,
            displayName: h.displayName,
            image: _avatarImage(h),
          ),
      ],
      admittedHelperCount: summary.admittedHelperCount,
      status: summary.status,
      phaseStatus: phaseStatusForHierarchyStatus(
        l10n,
        summary.status,
        statusChangedAt: summary.statusChangedAt,
        now: now,
      ),
      description: summary.description?.trim().isNotEmpty == true
          ? summary.description!.trim()
          : null,
      coverSource: summary.coverSource,
      coverImageId: summary.coverImageId,
      coverThumbImageId: summary.coverThumbImageId,
      primaryNeedSlug: summary.primaryNeedSlug,
      needs: summary.needs,
    );
  }

  factory BeaconRequestPreviewData.fromBeacon(
    L10n l10n,
    Beacon beacon, {
    required DateTime now,
    BeaconPhaseStatusPresentation? phaseStatus,
  }) {
    return BeaconRequestPreviewData(
      beaconId: beacon.id,
      title: beacon.title.trim().isNotEmpty
          ? beacon.title.trim()
          : l10n.beaconUntitled,
      author: beacon.author.id.isEmpty ? null : beacon.author,
      admittedHelpers: beacon.admittedHelperUsers,
      admittedHelperCount: beacon.admittedHelperCount,
      status: beacon.status,
      phaseStatus: phaseStatus ??
          phaseStatusForHierarchyStatus(
            l10n,
            beacon.status,
            statusChangedAt: beacon.statusChangedAt,
            now: now,
          ),
      description: beacon.description.trim().isNotEmpty
          ? beacon.description.trim()
          : null,
      coverSource: beacon.coverSource,
      coverImageId: beacon.coverImageId,
      coverThumbImageId: beacon.coverThumb?.id,
      primaryNeedSlug: beacon.primaryNeedSlug,
      needs: beacon.needs,
    );
  }

  static ImageEntity? _avatarImage(BeaconHierarchyOwnerSummary owner) {
    final id = owner.avatarImageId;
    if (id == null || id.isEmpty) return null;
    return ImageEntity(id: id, authorId: owner.id);
  }
}

BeaconCoordinationPhase phaseForHierarchyStatus(BeaconStatus status) =>
    switch (status) {
      BeaconStatus.draft => BeaconCoordinationPhase.draft,
      BeaconStatus.reviewOpen => BeaconCoordinationPhase.wrappingUp,
      BeaconStatus.closed => BeaconCoordinationPhase.closed,
      BeaconStatus.cancelled => BeaconCoordinationPhase.cancelled,
      BeaconStatus.deleted => BeaconCoordinationPhase.closed,
      _ => BeaconCoordinationPhase.openFloor,
    };

BeaconPhaseStatusPresentation phaseStatusForHierarchyStatus(
  L10n l10n,
  BeaconStatus status, {
  DateTime? statusChangedAt,
  required DateTime now,
}) {
  final terminal = status.isTerminal;
  return formatBeaconPhaseStatus(
    l10n,
    BeaconCoordinationPhaseResult(
      phase: phaseForHierarchyStatus(status),
      suggestedAction: BeaconPhasePrimaryAction.none,
      rowHarmony: BeaconPhaseRowHarmony.empty,
      lifecycleEndedAt: terminal ? statusChangedAt : null,
      slot2Kind: terminal && statusChangedAt != null
          ? BeaconPhaseSlot2Kind.lifecycleEndedAt
          : BeaconPhaseSlot2Kind.none,
    ),
    now: now,
  );
}

BeaconIdentity resolveRequestPreviewIdentity(
  BeaconRequestPreviewData data, {
  required bool allowPhoto,
}) {
  if (allowPhoto && data.coverSource == BeaconCoverSource.photo) {
    final thumbId = data.coverThumbImageId;
    if (thumbId != null && thumbId.isNotEmpty) {
      return BeaconIdentityPhoto(
        ImageEntity(
          id: thumbId,
          authorId: data.author?.id ?? '',
        ),
      );
    }
    final coverId = data.coverImageId;
    if (coverId != null && coverId.isNotEmpty) {
      return BeaconIdentityPhoto(
        ImageEntity(
          id: coverId,
          authorId: data.author?.id ?? '',
        ),
      );
    }
  }
  final slug = data.primaryNeedSlug;
  if (slug != null && data.needs.contains(slug)) {
    final tag = CapabilityTag.fromSlug(slug);
    if (tag != null) return BeaconIdentitySymbol(tag);
  }
  return const BeaconIdentityNeutral();
}

String requestPreviewImageUrl({
  required String ownerId,
  required String imageId,
}) =>
    '$kImageServer/$kImagesPath/$ownerId/$imageId.$kImageExt';

/// Shared request-list identity: tile, title, status, named people, face pile.
///
/// Desk wrappers supply [trailing] (overflow menu). Child cards pass
/// [showDescription] and omit trailing.
class BeaconRequestPreviewIdentity extends StatelessWidget {
  const BeaconRequestPreviewIdentity({
    required this.data,
    required this.currentUserId,
    this.trailing,
    this.titleMaxLines = 2,
    this.showDescription = false,
    this.identitySize = kBeaconCardHeaderIconSize,
    this.statusSemanticsIdentifier,
    super.key,
  });

  final BeaconRequestPreviewData data;
  final String currentUserId;
  final Widget? trailing;
  final int titleMaxLines;
  final bool showDescription;
  final double identitySize;
  final String? statusSemanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = data.author;
    final helpers = data.admittedHelpers;
    final firstHelper = helpers.isEmpty ? null : helpers.first;

    final titleStyle = theme.textTheme.titleSmall!.copyWith(
      color: scheme.onSurface,
    );

    final statusLine = data.phaseStatus.statusLine.trim();
    Widget? statusText;
    if (statusLine.isNotEmpty) {
      statusText = TenturaStatusLine(
        slot1: data.phaseStatus.slot1,
        slot2: data.phaseStatus.slot2,
        slot1Tone: data.phaseStatus.slot1Tone,
        slot2Tone: data.phaseStatus.slot2Tone,
        maxLines: null,
        overflow: TextOverflow.visible,
      );
      final id = statusSemanticsIdentifier;
      if (id != null) {
        statusText = Semantics(identifier: id, child: statusText);
      }
    }

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.title.isEmpty ? '—' : data.title,
          style: titleStyle,
          maxLines: titleMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
        if (statusText != null) statusText,
      ],
    );

    final identity = resolveRequestPreviewIdentity(data, allowPhoto: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewIdentityTile(
              data: data,
              identity: identity,
              size: identitySize,
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(child: titleColumn),
            if (trailing != null) ...[
              SizedBox(width: tt.tightGap),
              SizedBox(
                width: kBeaconCardMenuSlotWidth,
                height: kBeaconCardMenuSlotHeight,
                child: trailing,
              ),
            ],
          ],
        ),
        if (author != null) ...[
          SizedBox(height: tt.tightGap),
          Text(
            l10n.constellationPreviewAuthorLine(author.displayName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (firstHelper != null) ...[
          SizedBox(height: tt.tightGap / 2),
          Text(
            l10n.beaconChildCardWithHelper(firstHelper.displayName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (_hasFacePile) ...[
          SizedBox(height: tt.rowGap),
          _PreviewFacePile(
            author: author,
            helpers: helpers,
            helperCount: data.admittedHelperCount,
            currentUserId: currentUserId,
          ),
        ],
        if (showDescription && data.description != null) ...[
          SizedBox(height: tt.rowGap),
          Text(
            data.description!,
            style: TenturaText.bodySmall(scheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  bool get _hasFacePile {
    final author = data.author;
    if (author == null) return data.admittedHelpers.isNotEmpty;
    final display = beaconInvolvedPeopleDisplay(
      author: author,
      helpOfferUsers: data.admittedHelpers,
      helpOfferCount: data.admittedHelperCount,
    );
    return display.visible.isNotEmpty;
  }
}

class _PreviewIdentityTile extends StatelessWidget {
  const _PreviewIdentityTile({
    required this.data,
    required this.identity,
    required this.size,
  });

  final BeaconRequestPreviewData data;
  final BeaconIdentity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = switch (identity) {
      BeaconIdentitySymbol(:final tag) when l10n != null =>
        '${data.title}, ${tag.labelOf(l10n)}',
      _ => data.title,
    };
    return TenturaIdentityTileFrame(
      size: size,
      semanticsLabel: label,
      child: _content(context, identity),
    );
  }

  Widget _content(BuildContext context, BeaconIdentity identity) =>
      switch (identity) {
        BeaconIdentityPhoto(:final image) => _photo(context, image),
        BeaconIdentitySymbol(:final tag) => TenturaCapabilityGlyph(
          tag: tag,
          size: size,
        ),
        BeaconIdentityNeutral() => _neutral(context),
      };

  Widget _photo(BuildContext context, ImageEntity image) {
    final cacheExtent = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final ownerId = image.authorId.isNotEmpty
        ? image.authorId
        : (data.author?.id ?? '');
    return Image.network(
      requestPreviewImageUrl(ownerId: ownerId, imageId: image.id),
      fit: BoxFit.cover,
      width: size,
      height: size,
      cacheWidth: cacheExtent,
      cacheHeight: cacheExtent,
      errorBuilder: (_, _, _) => _photoErrorFallback(context, image),
    );
  }

  Widget _photoErrorFallback(BuildContext context, ImageEntity failed) {
    final thumbId = data.coverThumbImageId;
    final coverId = data.coverImageId;
    if (thumbId != null &&
        failed.id == thumbId &&
        coverId != null &&
        coverId != thumbId) {
      return _photo(
        context,
        ImageEntity(id: coverId, authorId: data.author?.id ?? ''),
      );
    }
    return _content(
      context,
      resolveRequestPreviewIdentity(data, allowPhoto: false),
    );
  }

  Widget _neutral(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.campaign_outlined,
          size: size * 0.52,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PreviewFacePile extends StatelessWidget {
  const _PreviewFacePile({
    required this.author,
    required this.helpers,
    required this.helperCount,
    required this.currentUserId,
  });

  final Profile? author;
  final List<Profile> helpers;
  final int helperCount;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final metaAvatar = context.tt.metadataAvatarSize;
    if (author == null) {
      final visible = helpers.take(kBeaconInvolvedPeopleMaxVisible).toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      final overflow = helperCount > visible.length
          ? helperCount - visible.length
          : 0;
      return OverlappingPeopleAvatars(
        profiles: visible,
        overflowCount: overflow,
        size: metaAvatar,
        selfUserId: currentUserId,
        semanticsLabel: l10n.facepileSemantics(visible.length, overflow),
      );
    }
    final display = beaconInvolvedPeopleDisplay(
      author: author!,
      helpOfferUsers: helpers,
      helpOfferCount: helperCount,
    );
    if (display.visible.isEmpty) return const SizedBox.shrink();
    return OverlappingPeopleAvatars(
      profiles: display.visible,
      overflowCount: display.overflow,
      size: metaAvatar,
      starredProfileId: author!.id,
      selfUserId: currentUserId,
      semanticsLabel: l10n.facepileSemantics(
        display.visible.length,
        display.overflow,
      ),
    );
  }
}
