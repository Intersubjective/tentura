import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_trust_badge.dart';
import '../../domain/entity/constellation_field.dart';
import 'constellation_node_ring_layer.dart';
import 'constellation_request_status_marker.dart';
import 'constellation_tag_row.dart';

/// Combined accessibility label for a Constellation map node (body + pin/status).
///
/// [online]: the person is online now (their presence halo is drawn).
/// [ownTagNames]: the viewer's own tags on the person, in tag order; the
/// person's automatic tags follow them in the label.
String constellationNodeSemanticLabel({
  required L10n l10n,
  required TenturaTokens tt,
  required ConstellationCubit cubit,
  required NodeDetails node,
  bool online = false,
  List<String> ownTagNames = const [],
}) {
  return switch (node) {
    FieldPersonNode(:final person) => () {
      final field = cubit.state.field;
      final trust = field == null
          ? null
          : constellationTrustBadges(
              field: field,
              viewerId: cubit.viewerId,
            )[person.id];
      final pinState = cubit.fieldPersonById(person.id)?.pinState;
      final base = [
        if (pinState == 'tombstone')
          l10n.constellationPinAccountDeleted
        else
          person.shownName,
        if (pinState == 'blockedByMe') l10n.constellationPinBlocked,
        if (trust != null) constellationTrustBadgeLabel(l10n, trust),
        if (online) l10n.chatPresenceOnline,
      ].join(', ');
      final autoKinds = [
        for (final peer in field?.peers ?? const <ConstellationPerson>[])
          if (peer.id == person.id) ...peer.autoTagKinds,
      ];
      final tagParts = [
        if (ownTagNames.isNotEmpty)
          l10n.constellationNodeOwnTagsSemantics(ownTagNames.join(', ')),
        if (autoKinds.isNotEmpty)
          l10n.constellationNodeAutoTagsSemantics(
            [
              for (final kind in autoKinds)
                constellationAutoTagName(l10n, kind),
            ].join(', '),
          ),
      ];
      final labelled = tagParts.isEmpty
          ? base
          : '$base, ${tagParts.join('; ')}';
      if (cubit.isAnchored(ConstellationAnchorTarget.person(person.id))) {
        return '$labelled, ${l10n.constellationPinMarkerSemantics}';
      }
      return labelled;
    }(),
    FieldBeaconNode(request: final request?) => () {
      if (request.isPlaceholder) {
        return '${constellationPinStateLabel(l10n, request.pinState)}, '
            '${l10n.constellationPinMarkerSemantics}';
      }
      final title = request.title.trim();
      final titlePart = title.isEmpty
          ? l10n.beaconViewTitle
          : '${l10n.beaconViewTitle}: $title';
      final markerParts = constellationRequestMarkerSemantics(
        l10n: l10n,
        tt: tt,
        rawStatus: request.status,
        isPinned: cubit.isAnchored(
          ConstellationAnchorTarget.beacon(request.id),
        ),
      );
      if (markerParts.isEmpty) {
        return titlePart;
      }
      return '$titlePart, ${markerParts.join(', ')}';
    }(),
    FieldBeaconNode(post: final post?) => () {
      final excerpt = post.rootExcerpt.trim();
      final titlePart = excerpt.isEmpty
          ? l10n.postCreateMenuPost
          : '${l10n.postCreateMenuPost}: $excerpt';
      if (!cubit.isAnchored(ConstellationAnchorTarget.beacon(post.id))) {
        return titlePart;
      }
      return '$titlePart, ${l10n.constellationPinMarkerSemantics}';
    }(),
    _ => '',
  };
}
