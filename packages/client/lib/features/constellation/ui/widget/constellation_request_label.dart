import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

import 'constellation_request_status_marker.dart';

/// Short contribution text for a constellation request label or preview header.
String constellationNeedText(L10n l10n, ConstellationRequest request) {
  final slug = request.primaryNeedSlug?.trim();
  if (slug != null && slug.isNotEmpty) {
    final tag = CapabilityTag.fromSlug(slug);
    if (tag != null) {
      return tag.labelOf(l10n);
    }
  }
  final title = request.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  return l10n.constellationNeedUnspecified;
}

/// Timing snippet using beacon-schedule semantics (event vs deadline by nullability).
String? constellationTimingSnippet(
  L10n l10n,
  ConstellationRequest request, {
  DateTime? now,
}) {
  final beacon = _scheduleBeacon(request);
  final presentation = beaconSchedulePresentation(
    beacon: beacon,
    l10n: l10n,
    now: now,
  );
  return presentation?.visibleText;
}

/// Coverage snippet from author-supplied coordination status only — never from offer counts.
String? constellationCoverageSnippet(L10n l10n, ConstellationRequest request) {
  final status = BeaconStatus.fromSmallint(request.status);
  return switch (status) {
    BeaconStatus.needsMoreHelp => l10n.beaconPhaseNeedsMoreHelp,
    BeaconStatus.enoughHelp =>
      '${l10n.coordinationEnoughHelp} · ${l10n.constellationCoverageBackupsWelcome}',
    _ => null,
  };
}

/// UX1 satellite label: need · timing · coverage (unknown parts omitted).
String constellationRequestLabelText(
  L10n l10n,
  ConstellationRequest request, {
  DateTime? now,
}) {
  final parts = <String>[
    constellationNeedText(l10n, request),
    ?constellationTimingSnippet(l10n, request, now: now),
    ?constellationCoverageSnippet(l10n, request),
  ];
  return parts.join(' · ');
}

/// D16 held-state annotation shown alongside the request, never hiding it.
String? constellationHeldAnnotation(L10n l10n, ConstellationRequest request) {
  return switch (request.heldState) {
    ConstellationHeldState.mine => l10n.constellationHeldMine,
    ConstellationHeldState.offered => l10n.constellationHeldOffered,
    ConstellationHeldState.participant => l10n.constellationHeldParticipant,
    ConstellationHeldState.forwarded => l10n.constellationHeldForwarded,
    ConstellationHeldState.none => null,
  };
}

/// First-hop peer id on the selected path to [authorId], or null when direct / ego-owned.
String? constellationConnectionThroughPeerId({
  required String egoId,
  required String authorId,
  required Map<String, String> parent,
}) {
  if (authorId == egoId) {
    return null;
  }
  if (parent[authorId] == egoId) {
    return null;
  }
  var node = authorId;
  while (true) {
    final nextParent = parent[node];
    if (nextParent == null) {
      return null;
    }
    if (nextParent == egoId) {
      return node;
    }
    node = nextParent;
  }
}

/// Resolve the frozen §0.6 connection label, or null when no intermediary applies.
String? constellationConnectionLabelText(
  L10n l10n, {
  required String? throughPeerName,
}) {
  final name = throughPeerName?.trim();
  if (name == null || name.isEmpty) {
    return null;
  }
  return l10n.constellationConnectionLabel(name);
}

class ConstellationRequestLabel extends StatelessWidget {
  const ConstellationRequestLabel({
    required this.request,
    this.now,
    this.isPinned = false,
    super.key,
  });

  final ConstellationRequest request;
  final DateTime? now;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final annotation = constellationHeldAnnotation(l10n, request);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          constellationRequestLabelText(l10n, request, now: now),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.labelSmall(theme.colorScheme.onSurface),
        ),
        if (annotation != null) ...[
          SizedBox(height: context.tt.tightGap),
          TenturaStatusText(
            annotation,
            tone: TenturaTone.info,
            maxLines: 2,
            softWrap: true,
            textAlign: TextAlign.center,
          ),
        ],
        SizedBox(height: context.tt.tightGap),
        ConstellationRequestStatusMarker(
          rawStatus: request.status,
          isPinned: isPinned,
        ),
      ],
    );
  }
}

Beacon _scheduleBeacon(ConstellationRequest request) => Beacon(
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  startAt: request.startAt,
  endAt: request.endAt,
  status: BeaconStatus.fromSmallint(request.status),
);
