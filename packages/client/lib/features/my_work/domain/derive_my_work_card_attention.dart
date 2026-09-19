import 'dart:math' as math;

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';

/// Everything one My Desk card shows about attention — the rows it renders
/// **and** the two indicators it lights — derived once.
class MyWorkCardAttentionView {
  const MyWorkCardAttentionView({
    required this.obligations,
    required this.optionalEvents,
    required this.optionalTotal,
    required this.facts,
  });

  /// Live obligation receipts. The block groups them for display; the count
  /// stays on the receipts (§6 — obligations, not visual sub-card groups).
  final List<AttentionReceipt> obligations;

  /// Uncleared optional events the card can actually render.
  final List<AttentionReceipt> optionalEvents;

  /// The server's count of uncleared optional events.
  final int optionalTotal;

  final RequestAttentionFacts facts;
}

/// The one derivation behind a card's rows and its indicators (M1).
///
/// The dot is a function of [MyWorkCardAttentionView.optionalEvents] — the row
/// the card renders — not of the server total on its own. That is what makes a
/// lit-but-empty card unrepresentable here rather than merely untested: a
/// total with nothing to show lights nothing, and a row always lights.
MyWorkCardAttentionView myWorkCardAttentionView({
  required String beaconId,
  required MyWorkBeaconAttention? attention,
  required bool viewerArchived,
}) {
  final obligations =
      attention?.liveObligations ?? const <AttentionReceipt>[];
  final optionalEvents = <AttentionReceipt>[?attention?.latestUnseen];
  final serverTotal = attention?.unseenCount ?? 0;
  // A row in hand is worth at least one, whatever the total says.
  final optionalTotal = optionalEvents.isEmpty
      ? 0
      : math.max(serverTotal, optionalEvents.length);
  return MyWorkCardAttentionView(
    obligations: obligations,
    optionalEvents: optionalEvents,
    optionalTotal: optionalTotal,
    facts: RequestAttentionFacts(
      requestId: beaconId,
      unclearedOptionalEvents: optionalTotal,
      liveObligations: obligations.length,
      viewerArchived: viewerArchived,
    ),
  );
}
