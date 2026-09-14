import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'constellation_request_status_marker.dart';

/// Combined accessibility label for a Constellation map node (body + pin/status).
String constellationNodeSemanticLabel({
  required L10n l10n,
  required TenturaTokens tt,
  required ConstellationCubit cubit,
  required NodeDetails node,
}) {
  return switch (node) {
    FieldPersonNode(:final person) => () {
        final base = person.shownName;
        if (cubit.isAnchored(ConstellationAnchorTarget.person(person.id))) {
          return '$base, ${l10n.constellationPinMarkerSemantics}';
        }
        return base;
      }(),
    FieldRequestNode(:final request) => () {
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
    _ => '',
  };
}
