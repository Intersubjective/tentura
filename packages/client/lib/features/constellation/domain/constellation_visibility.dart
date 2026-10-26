import 'package:meta/meta.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart'
    show ConstellationEdgeRef;

import 'constellation_post_fade.dart' show constellationPostActive;
import 'constellation_trust_chain.dart';
import 'entity/constellation_anchor_projection.dart';
import 'entity/constellation_field.dart';

/// How far a person is from the viewer in visible trust (#645).
enum ConstellationTrustDegree {
  /// People the viewer trusts directly (#246).
  first,

  /// Two trust steps away (or reached only through a derived edge of the
  /// viewer's own).
  second,

  /// Three or more steps away, or with no chain of visible trust at all.
  further,
}

/// What the field shows (#645): global on/off switches for all Requests, all
/// Posts, and all people of each trust degree. Kept per viewer on this device.
/// Only the viewer's own node always stays.
@immutable
class ConstellationVisibility {
  const ConstellationVisibility({
    this.requests = true,
    this.posts = true,
    this.firstDegree = true,
    this.secondDegree = true,
    this.furtherDegrees = true,
  });

  /// Restores a stored value; anything missing or malformed shows.
  factory ConstellationVisibility.fromJson(Object? json) {
    if (json is! Map) {
      return all;
    }
    bool read(String key) {
      final value = json[key];
      return value is! bool || value;
    }

    return ConstellationVisibility(
      requests: read('requests'),
      posts: read('posts'),
      firstDegree: read('first'),
      secondDegree: read('second'),
      furtherDegrees: read('further'),
    );
  }

  static const all = ConstellationVisibility();

  final bool requests;
  final bool posts;
  final bool firstDegree;
  final bool secondDegree;
  final bool furtherDegrees;

  bool get showsEverything =>
      requests && posts && firstDegree && secondDegree && furtherDegrees;

  bool get hidesPeople => !(firstDegree && secondDegree && furtherDegrees);

  bool showsDegree(ConstellationTrustDegree degree) => switch (degree) {
    ConstellationTrustDegree.first => firstDegree,
    ConstellationTrustDegree.second => secondDegree,
    ConstellationTrustDegree.further => furtherDegrees,
  };

  ConstellationVisibility withDegree(
    ConstellationTrustDegree degree, {
    required bool shown,
  }) => copyWith(
    firstDegree: degree == ConstellationTrustDegree.first ? shown : null,
    secondDegree: degree == ConstellationTrustDegree.second ? shown : null,
    furtherDegrees: degree == ConstellationTrustDegree.further ? shown : null,
  );

  ConstellationVisibility copyWith({
    bool? requests,
    bool? posts,
    bool? firstDegree,
    bool? secondDegree,
    bool? furtherDegrees,
  }) => ConstellationVisibility(
    requests: requests ?? this.requests,
    posts: posts ?? this.posts,
    firstDegree: firstDegree ?? this.firstDegree,
    secondDegree: secondDegree ?? this.secondDegree,
    furtherDegrees: furtherDegrees ?? this.furtherDegrees,
  );

  Map<String, Object?> toJson() => {
    'requests': requests,
    'posts': posts,
    'first': firstDegree,
    'second': secondDegree,
    'further': furtherDegrees,
  };

  @override
  bool operator ==(Object other) =>
      other is ConstellationVisibility &&
      other.requests == requests &&
      other.posts == posts &&
      other.firstDegree == firstDegree &&
      other.secondDegree == secondDegree &&
      other.furtherDegrees == furtherDegrees;

  @override
  int get hashCode =>
      Object.hash(requests, posts, firstDegree, secondDegree, furtherDegrees);
}

/// Ids of the contact nodes without content in [field] (#246): identity only,
/// no trust edges of their own.
Set<String> constellationContactOnlyIds(ConstellationField field) => {
  for (final peer in field.peers)
    if (peer.contactOnly) peer.id,
  for (final peer in field.resolvedAnchorProjection.pinnedPeers)
    if (peer.contactOnly) peer.id,
};

/// The trust edges [field] lets the viewer see: the field's edges and the
/// anchor support paths. Nothing else is ever fetched for this.
List<ConstellationEdgeRef> constellationVisibleTrustEdges(
  ConstellationField field,
) => [
  for (final edge in field.edges)
    (src: edge.src, dst: edge.dst, tier: edge.tier),
  for (final edge in field.resolvedAnchorProjection.supportEdges)
    (src: edge.src, dst: edge.dst, tier: edge.tier),
];

/// Every person of [field] (except the viewer) by trust degree, from the
/// trust edges the viewer may see only (#645):
///
/// * first: the viewer's direct contacts (`directContactIds`, plus anyone
///   the viewer has an explicit edge to);
/// * second: two steps along visible trust, or one step through a derived
///   edge of the viewer's;
/// * further: three or more steps, or no visible chain at all.
///
/// A contact node without content is first degree (the viewer's own edge),
/// and no one is reached through it.
Map<String, ConstellationTrustDegree> constellationTrustDegrees({
  required ConstellationField field,
  required String viewerId,
}) {
  final edges = constellationVisibleTrustEdges(field);
  final direct = {
    ...field.directContactIds,
    for (final edge in edges)
      if (edge.src == viewerId && edge.tier == 1) edge.dst,
  };
  final hops = constellationTrustHops(
    from: viewerId,
    edges: edges,
    contactOnlyIds: constellationContactOnlyIds(field),
  );
  final projection = field.resolvedAnchorProjection;
  final ids = {
    for (final peer in field.peers) peer.id,
    for (final peer in projection.pinnedPeers) peer.id,
    for (final peer in projection.supportPeers) peer.id,
    for (final request in field.requests) request.authorId,
    for (final request in projection.pinnedRequests) request.authorId,
    for (final post in field.posts) post.authorId,
  }..remove(viewerId);
  return {
    for (final id in ids)
      id: direct.contains(id)
          ? ConstellationTrustDegree.first
          : switch (hops[id]) {
              final h? when h <= 2 => ConstellationTrustDegree.second,
              _ => ConstellationTrustDegree.further,
            },
  };
}

/// [field] with what [visibility] hides taken out, before the field is
/// composed, so the map and the list (which share the composition) agree.
///
/// The toggles are global (owner, #645): a hidden type hides every object of
/// it, pinned ones included. Hidden people go with their Requests, Posts,
/// trust edges and support paths. Only the viewer always stays. Pins are not
/// touched: this is presentation only, so a hidden pinned node comes back at
/// its pin when its type is shown again.
ConstellationField constellationVisibleField({
  required ConstellationField field,
  required String viewerId,
  required ConstellationVisibility visibility,
  Map<String, ConstellationTrustDegree>? degrees,
}) {
  if (visibility.showsEverything) {
    return field;
  }
  final byDegree = !visibility.hidesPeople
      ? const <String, ConstellationTrustDegree>{}
      : degrees ?? constellationTrustDegrees(field: field, viewerId: viewerId);
  bool shown(String personId) =>
      personId == viewerId ||
      !visibility.hidesPeople ||
      visibility.showsDegree(
        byDegree[personId] ?? ConstellationTrustDegree.further,
      );
  bool requestShown(ConstellationRequest request) =>
      visibility.requests && shown(request.authorId);

  final requests = field.requests.where(requestShown).toList();
  final posts = [
    for (final post in field.posts)
      if (visibility.posts && shown(post.authorId)) post,
  ];
  final keptBeaconIds = {
    for (final request in requests) request.id,
    for (final post in posts) post.id,
  };
  final projection = field.anchorProjection;
  final pinnedRequests =
      projection?.pinnedRequests.where(requestShown).toList() ?? const [];
  final shownPinnedRequestIds = {
    for (final request in pinnedRequests) request.id,
  };
  final hiddenBeaconIds = {
    for (final request in field.requests)
      if (!keptBeaconIds.contains(request.id)) request.id,
    for (final post in field.posts)
      if (!keptBeaconIds.contains(post.id)) post.id,
    for (final request
        in projection?.pinnedRequests ?? const <ConstellationRequest>[])
      if (!shownPinnedRequestIds.contains(request.id)) request.id,
  };
  return field.copyWith(
    peers: [
      for (final peer in field.peers)
        if (shown(peer.id)) peer,
    ],
    edges: [
      for (final edge in field.edges)
        if (shown(edge.src) && shown(edge.dst)) edge,
    ],
    requests: requests,
    posts: posts,
    memberWebs: [
      for (final web in field.memberWebs)
        if (keptBeaconIds.contains(web.beaconId) && shown(web.personId)) web,
    ],
    directContactIds: [
      for (final id in field.directContactIds)
        if (shown(id)) id,
    ],
    anchorProjection: projection == null
        ? null
        : ConstellationAnchorProjection(
            revision: projection.revision,
            anchors: [
              for (final anchor in projection.anchors)
                if (switch (anchor.target.kind) {
                  ConstellationAnchorTargetKind.person => shown(
                    anchor.target.id,
                  ),
                  ConstellationAnchorTargetKind.beacon =>
                    !hiddenBeaconIds.contains(anchor.target.id),
                })
                  anchor,
            ],
            pinnedPeers: [
              for (final peer in projection.pinnedPeers)
                if (shown(peer.id)) peer,
            ],
            pinnedRequests: pinnedRequests,
            supportPeers: [
              for (final peer in projection.supportPeers)
                if (shown(peer.id)) peer,
            ],
            supportEdges: [
              for (final edge in projection.supportEdges)
                if (shown(edge.src) && shown(edge.dst)) edge,
            ],
            serverFilteredBeaconIds: projection.serverFilteredBeaconIds,
            serverFilteredBeaconCount: projection.serverFilteredBeaconCount,
          ),
  );
}

/// People whose Requests or Posts [visibility] hides by type while their
/// degree stays shown (#645): the field composes them as holders anyway, so
/// switching content off never takes a shown person off the field. Mirrors
/// what made them holders with everything shown: an own or pinned Request,
/// or a Post the field could draw (active, or pinned).
Set<String> constellationHiddenItemHolderIds({
  required ConstellationField field,
  required String viewerId,
  required ConstellationVisibility visibility,
  DateTime? asOfUtc,
  Map<String, ConstellationTrustDegree>? degrees,
}) {
  if (visibility.requests && visibility.posts) {
    return const {};
  }
  final byDegree = !visibility.hidesPeople
      ? const <String, ConstellationTrustDegree>{}
      : degrees ?? constellationTrustDegrees(field: field, viewerId: viewerId);
  bool shown(String personId) =>
      personId != viewerId &&
      (!visibility.hidesPeople ||
          visibility.showsDegree(
            byDegree[personId] ?? ConstellationTrustDegree.further,
          ));
  final projection = field.resolvedAnchorProjection;
  final anchoredBeaconIds = {
    for (final anchor in projection.anchors)
      if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
        anchor.target.id,
  };
  return {
    if (!visibility.requests)
      for (final request in [...field.requests, ...projection.pinnedRequests])
        if (shown(request.authorId)) request.authorId,
    if (!visibility.posts)
      for (final post in field.posts)
        if (shown(post.authorId) &&
            (constellationPostActive(post, asOfUtc ?? field.loadedAt) ||
                (post.isPinned && anchoredBeaconIds.contains(post.id))))
          post.authorId,
  };
}

/// How many objects of each toggle the field holds (#645), for the counts on
/// the show/hide chips: the people the field places when everything is shown
/// (`peopleOnField`) by degree, and their Requests and the Posts the field can
/// draw (active, or pinned). Request filters do not change the counts.
typedef ConstellationVisibilityCounts = ({
  int requests,
  int posts,
  Map<ConstellationTrustDegree, int> people,
});

ConstellationVisibilityCounts constellationVisibilityCounts({
  required ConstellationField field,
  required String viewerId,
  required Set<String> peopleOnField,
  required DateTime asOfUtc,
  Map<String, ConstellationTrustDegree>? degrees,
}) {
  final byDegree =
      degrees ?? constellationTrustDegrees(field: field, viewerId: viewerId);
  final people = {
    for (final degree in ConstellationTrustDegree.values) degree: 0,
  };
  for (final id in peopleOnField) {
    if (id == viewerId) continue;
    final degree = byDegree[id] ?? ConstellationTrustDegree.further;
    people[degree] = people[degree]! + 1;
  }
  bool placed(String authorId) =>
      authorId == viewerId || peopleOnField.contains(authorId);
  final projection = field.resolvedAnchorProjection;
  final requestIds = {
    for (final request in [...field.requests, ...projection.pinnedRequests])
      if (placed(request.authorId)) request.id,
  };
  final anchoredBeaconIds = {
    for (final anchor in projection.anchors)
      if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
        anchor.target.id,
  };
  final posts = [
    for (final post in field.posts)
      if (placed(post.authorId) &&
          (constellationPostActive(post, asOfUtc) ||
              (post.isPinned && anchoredBeaconIds.contains(post.id))))
        post,
  ];
  return (requests: requestIds.length, posts: posts.length, people: people);
}
