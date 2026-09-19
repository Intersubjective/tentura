import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/for_you_stream_entries.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../bloc/activity_offers_state.dart';
import 'request_attention_card.dart';

/// Everything one [RequestAttentionCard] needs, from either of the two shapes
/// For You holds a Request in.
///
/// Two shapes, because the pinned zone and the stream are different queries:
/// the pinned zone hydrates a real [Beacon] and an [InboxProvenance] from the
/// offers API, while a grouped `requestActivity` row carries flattened beacon
/// columns and a `provenanceJson` string. One card, so one model.
class RequestAttentionCardModel {
  const RequestAttentionCardModel({
    required this.beacon,
    required this.facts,
    required this.variant,
    this.relation = RequestAttentionRelation.none,
    this.provenance = InboxProvenance.empty,
    this.representative,
    this.eventTotal = 0,
    this.eventsPreview = const [],
    this.allowsForward = false,
  });

  final Beacon beacon;
  final RequestAttentionFacts facts;
  final RequestAttentionCardVariant variant;
  final RequestAttentionRelation relation;
  final InboxProvenance provenance;
  final AttentionReceipt? representative;
  final int eventTotal;
  final List<AttentionReceipt> eventsPreview;

  /// Whether «Переслать» is offered. [Beacon.allowsForward] is derived from
  /// [Beacon.status], which a grouped row does not carry — the server sends
  /// the answer instead, so it is held here rather than faked onto a status.
  final bool allowsForward;
}

/// The grouped variant (§9): already answered, events under the header, no
/// action row.
///
/// Null when the row is not about a Request — a card with no Request to head
/// it is not a card, and the stream keeps such a row as a feed tile.
RequestAttentionCardModel? requestCardFromReceipt(
  AttentionReceipt receipt, {
  ForYouStreamRelation relation = ForYouStreamRelation.none,
}) {
  final beaconId = receipt.beaconId ?? '';
  if (beaconId.isEmpty) return null;

  final authorId = receipt.beaconAuthorId ?? '';
  final unseen = receipt.eventUnseenCount ?? 0;

  return RequestAttentionCardModel(
    beacon: Beacon(
      id: beaconId,
      title: receipt.title,
      createdAt: receipt.createdAt,
      updatedAt: receipt.createdAt,
      endAt: receipt.beaconEndAt,
      coverImageId: _nonEmpty(receipt.beaconImageId),
      author: Profile(
        id: authorId,
        displayName: receipt.beaconAuthorName ?? '',
        image: _imageOf(receipt.beaconAuthorImageId, authorId),
      ),
    ),
    // The dot is the server's uncleared-optional count for this Request, the
    // same number the row's `is_active_attention` is computed from (§6 M1) —
    // not a second reading of it.
    facts: RequestAttentionFacts(
      requestId: beaconId,
      unclearedOptionalEvents: unseen,
    ),
    variant: RequestAttentionCardVariant.grouped,
    relation: switch (relation) {
      ForYouStreamRelation.none => RequestAttentionRelation.none,
      ForYouStreamRelation.helping => RequestAttentionRelation.helping,
      ForYouStreamRelation.following => RequestAttentionRelation.following,
    },
    provenance: InboxProvenance.parse(receipt.provenanceJson),
    representative: receipt,
    eventTotal: receipt.eventTotal ?? receipt.eventsPreview.length,
    eventsPreview: receipt.eventsPreview,
    allowsForward: receipt.allowsForward ?? false,
  );
}

/// The pinned variant (§9): an unanswered forward, whose action row is the
/// whole point and which carries no relation chip yet, by definition.
RequestAttentionCardModel? requestCardFromInboxItem(
  InboxItem item, {
  ActivityOfferBeaconMeta? meta,
}) {
  final beacon = item.beacon;
  if (beacon == null) return null;

  return RequestAttentionCardModel(
    beacon: beacon,
    facts: RequestAttentionFacts(
      requestId: item.beaconId,
      unclearedOptionalEvents: meta?.eventUnseenCount ?? 0,
      // The pinned zone *is* the set of forwards awaiting a decision, so this
      // is what lights For You for them (§6 `for you.dot`).
      pendingForward: true,
    ),
    variant: RequestAttentionCardVariant.pinned,
    provenance: item.provenance,
    eventTotal: meta?.eventTotal ?? 0,
    eventsPreview: meta?.eventsPreview ?? const [],
    allowsForward: beacon.allowsForward,
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty || value == 'null' ? null : value;

ImageEntity? _imageOf(String? imageId, String authorId) {
  final id = _nonEmpty(imageId);
  if (id == null || authorId.isEmpty) return null;
  return ImageEntity(id: id, authorId: authorId);
}
