import 'package:meta/meta.dart';

import 'constellation_anchor_projection.dart';
import 'gql_public/image_public_record.dart';

@immutable
class ConstellationFieldSnapshot {
  ConstellationFieldSnapshot({
    required this.loadedAt,
    required this.context,
    required this.peers,
    required this.edges,
    required this.requests,
    required this.peersCapped,
    required this.requestsCapped,
    this.posts = const [],
    this.memberWebs = const [],
    ConstellationAnchorProjection? anchorProjection,
  }) : anchorProjection = anchorProjection ?? ConstellationAnchorProjection.empty;

  final DateTime loadedAt;
  final String context;
  final List<ConstellationPeerRecord> peers;
  final List<ConstellationEdgeRecord> edges;
  final List<ConstellationRequestRecord> requests;
  final bool peersCapped;
  final bool requestsCapped;
  final List<ConstellationPostRecord> posts;
  final List<ConstellationMemberWebRecord> memberWebs;
  final ConstellationAnchorProjection anchorProjection;
}

@immutable
class ConstellationPostRecord {
  const ConstellationPostRecord({
    required this.id,
    required this.authorId,
    required this.lastActivityAt,
    required this.rootExcerpt,
    required this.isPinned,
    required this.hiddenReachCount,
  });

  final String id;
  final String authorId;
  final DateTime lastActivityAt;
  final String rootExcerpt;
  final bool isPinned;

  /// Members of the Post outside the viewer's visible peer set.
  final int hiddenReachCount;
}

/// `inside`: the author, or an admitted member who opened the Post;
/// `forwarded`: a recipient of an active forward edge who has not opened it.
enum ConstellationMemberWebState { forwarded, inside }

@immutable
class ConstellationMemberWebRecord {
  const ConstellationMemberWebRecord({
    required this.beaconId,
    required this.personId,
    required this.state,
  });

  final String beaconId;
  final String personId;
  final ConstellationMemberWebState state;
}

@immutable
class ConstellationPeerRecord {
  const ConstellationPeerRecord({
    required this.id,
    this.displayName,
    this.handle,
    this.image,
  });

  final String id;
  final String? displayName;
  final String? handle;
  final ImagePublicRecord? image;
}

@immutable
class ConstellationEdgeRecord {
  const ConstellationEdgeRecord({
    required this.src,
    required this.dst,
    required this.tier,
  });

  final String src;
  final String dst;
  final int tier;
}

@immutable
class ConstellationRequestRecord {
  const ConstellationRequestRecord({
    required this.id,
    required this.authorId,
    required this.title,
    required this.status,
    required this.needs,
    this.primaryNeedSlug,
    this.startAt,
    this.endAt,
    this.addressLabel,
    required this.hasCoordinates,
    required this.isMine,
    required this.viewerHasActiveHelpOffer,
    required this.viewerIsRoomParticipant,
    required this.viewerHasForwardEdge,
    required this.helpOfferCount,
    this.kind = 0,
    this.coverSource = 0,
    this.coverThumb,
    this.viewerParticipates,
  });

  final String id;
  final String authorId;
  final String title;
  final int status;
  final List<String> needs;
  final String? primaryNeedSlug;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? addressLabel;
  final bool hasCoordinates;
  final bool isMine;
  final bool viewerHasActiveHelpOffer;
  final bool viewerIsRoomParticipant;
  final bool viewerHasForwardEdge;
  final int helpOfferCount;
  /// Wire: 0 = Request, 1 = Post (matches `beacon.kind`).
  final int kind;
  /// Wire: 0 = photo, 1 = symbol (matches `beacon.cover_source`).
  final int coverSource;
  final ImagePublicRecord? coverThumb;
  /// When set (pinned batch load), full C2 participation predicate; otherwise null.
  final bool? viewerParticipates;
}
