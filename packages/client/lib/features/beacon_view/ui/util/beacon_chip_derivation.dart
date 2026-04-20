import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';

/// Client-side chip labels for the beacon operational header (no backend fields).
class BeaconDerivedChip {
  const BeaconDerivedChip({
    required this.label,
    this.emphasized = false,
  });

  final String label;
  final bool emphasized;
}

int activeCommitmentCount(List<TimelineCommitment> commitments) =>
    commitments.where((c) => !c.isWithdrawn).length;

int usefulCommitmentCount(List<TimelineCommitment> commitments) => commitments
    .where((c) => !c.isWithdrawn && c.coordinationResponse == CoordinationResponseType.useful)
    .length;

int withdrawnCommitmentCount(List<TimelineCommitment> commitments) =>
    commitments.where((c) => c.isWithdrawn).length;

/// Distinct forwarders toward the viewer (edges where viewer is recipient).
int distinctForwarderCountTowardViewer({
  required List<ForwardEdge> viewerForwardEdges,
  required String myUserId,
}) {
  final ids = <String>{};
  for (final e in viewerForwardEdges) {
    if (e.recipient.id == myUserId && e.sender.id.isNotEmpty) {
      ids.add(e.sender.id);
    }
  }
  return ids.length;
}

List<BeaconDerivedChip> deriveSupportingChips({
  required L10n l10n,
  required Beacon beacon,
  required List<TimelineCommitment> commitments,
  required List<ForwardEdge> viewerForwardEdges,
  required String myUserId,
  required bool isAuthorView,
}) {
  final out = <BeaconDerivedChip>[];

  final n = activeCommitmentCount(commitments);
  if (n > 0) {
    out.add(BeaconDerivedChip(label: l10n.beaconChipCommitsCount(n)));
  }

  final u = usefulCommitmentCount(commitments);
  if (u > 0) {
    out.add(BeaconDerivedChip(label: l10n.beaconChipUsefulCount(u)));
  }

  out.addAll(_missingHelpChips(l10n, beacon.coordinationStatus, commitments));

  final helpTypes = commitments
      .where((c) => !c.isWithdrawn)
      .map((c) => c.helpType)
      .whereType<String>()
      .toSet();
  for (final ht in helpTypes) {
    final lbl = helpTypeLabel(l10n, ht);
    if (lbl != null && lbl.isNotEmpty) {
      out.add(BeaconDerivedChip(label: l10n.beaconChipHelpTypeCommitted(lbl)));
    }
  }

  if (!isAuthorView) {
    final fwd = distinctForwarderCountTowardViewer(
      viewerForwardEdges: viewerForwardEdges,
      myUserId: myUserId,
    );
    if (fwd > 0) {
      out.add(BeaconDerivedChip(label: l10n.beaconChipForwardedBy(fwd)));
    }
  } else if (beacon.lifecycle == BeaconLifecycle.open) {
    final mySent = viewerForwardEdges.where((e) => e.sender.id == myUserId).length;
    if (mySent > 0) {
      out.add(BeaconDerivedChip(label: l10n.beaconChipYouForwarded(mySent)));
    }
  }

  final end = beacon.endAt;
  if (end != null) {
    out.add(
      BeaconDerivedChip(
        label: l10n.beaconChipDeadlineOn(dateFormatYMD(end)),
        emphasized: true,
      ),
    );
  }

  return out;
}

List<BeaconDerivedChip> _missingHelpChips(
  L10n l10n,
  BeaconCoordinationStatus status,
  List<TimelineCommitment> commitments,
) {
  switch (status) {
    case BeaconCoordinationStatus.moreOrDifferentHelpNeeded:
      return [BeaconDerivedChip(label: l10n.beaconChipMoreHelpNeeded, emphasized: true)];
    case BeaconCoordinationStatus.commitmentsWaitingForReview:
      return [BeaconDerivedChip(label: l10n.beaconChipReviewingCommitments)];
    case BeaconCoordinationStatus.enoughHelpCommitted:
      if (activeCommitmentCount(commitments) == 0) {
        return [];
      }
      return [BeaconDerivedChip(label: l10n.beaconChipEnoughHelp)];
    case BeaconCoordinationStatus.noCommitmentsYet:
      return [];
  }
}

String? firstParagraphNeedLine(Beacon beacon) {
  final d = beacon.description.trim();
  if (d.isEmpty) return null;
  final i = d.indexOf('\n');
  if (i < 0) return d;
  return d.substring(0, i).trim();
}

TimelineUpdate? latestTimelineUpdate(Iterable<TimelineEntry> timeline) {
  TimelineUpdate? latest;
  for (final e in timeline) {
    if (e is TimelineUpdate) {
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) {
        latest = e;
      }
    }
  }
  return latest;
}
