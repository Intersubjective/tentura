import 'dart:math' as math;

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';

import 'derive_my_work_plan_rows.dart';

/// Everything one My Desk card shows about attention — the rows it renders
/// **and** the two indicators it lights — derived once.
class MyWorkCardAttentionView {
  const MyWorkCardAttentionView({
    required this.obligations,
    required this.optionalEvents,
    required this.optionalTotal,
    required this.facts,
    this.hasPlanRows = false,
  });

  /// Live obligation receipts. The block groups them for display; the count
  /// stays on the receipts (§6 — obligations, not visual sub-card groups).
  final List<AttentionReceipt> obligations;

  /// Uncleared optional events the card can actually render.
  final List<AttentionReceipt> optionalEvents;

  /// The server's count of uncleared optional events.
  final int optionalTotal;

  final RequestAttentionFacts facts;

  /// The card shows Request plan rows (#220 §5.8); the plan receipts they
  /// stand for are then left out of [obligations] and [optionalEvents].
  final bool hasPlanRows;
}

/// The one derivation behind a card's rows and its indicators (M1).
///
/// The dot is a function of [MyWorkCardAttentionView.optionalEvents] — the row
/// the card renders — not of the server total on its own. That is what makes a
/// lit-but-empty card unrepresentable here rather than merely untested: a
/// total with nothing to show lights nothing, and a row always lights.
///
/// With [planSlice] (and the [now] its rows are derived at), the plan rows
/// stand for the plan receipts (#220 §5.8): those stay in the facts, not in
/// the rows.
MyWorkCardAttentionView myWorkCardAttentionView({
  required String beaconId,
  required MyWorkBeaconAttention? attention,
  required bool viewerArchived,
  PlanViewerSlice? planSlice,
  DateTime? now,
}) {
  final obligations = attention?.liveObligations ?? const <AttentionReceipt>[];
  final optionalEvents = <AttentionReceipt>[?attention?.latestUnseen];
  final serverTotal = attention?.unseenCount ?? 0;
  // A row in hand is worth at least one, whatever the total says.
  final optionalTotal = optionalEvents.isEmpty
      ? 0
      : math.max(serverTotal, optionalEvents.length);
  final facts = RequestAttentionFacts(
    requestId: beaconId,
    unclearedOptionalEvents: optionalTotal,
    liveObligations: obligations.length,
    viewerArchived: viewerArchived,
  );
  final hasPlanRows =
      planSlice != null &&
      now != null &&
      planSlice.hasViewerRows &&
      deriveMyWorkPlanRows(planSlice, now).isNotEmpty;
  if (!hasPlanRows) {
    return MyWorkCardAttentionView(
      obligations: obligations,
      optionalEvents: optionalEvents,
      optionalTotal: optionalTotal,
      facts: facts,
    );
  }
  final shownEvents = [
    for (final r in optionalEvents)
      if (!myWorkReceiptShownAsPlanRow(r)) r,
  ];
  final hidden = optionalEvents.length - shownEvents.length;
  return MyWorkCardAttentionView(
    obligations: [
      for (final r in obligations)
        if (!myWorkReceiptShownAsPlanRow(r)) r,
    ],
    optionalEvents: shownEvents,
    optionalTotal: math.max(0, optionalTotal - hidden),
    facts: facts,
    hasPlanRows: true,
  );
}
