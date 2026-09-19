/// The one rule behind every attention list and every attention indicator.
///
/// M1 (`docs/features/request-attention.md` §6, design D09): *the rule deciding
/// what a list shows by default and the rule behind its indicator are the same
/// rule, implemented once*. The failure this prevents is a tab that lights and
/// then shows nothing to act on — so the indicator is not computed from the
/// facts directly. It is computed from the **membership list**
/// ([myDeskAttentionMembers] / [forYouAttentionMembers]) that the surface
/// itself renders, which makes "lit but empty" unrepresentable rather than
/// merely untested.
///
/// Dot and count are independent (D09): a Request with both shows both, and a
/// surface shows its dot whether or not it also shows a number. Nothing here
/// takes the active tab as an input — indicators do not hide because the tab is
/// currently open.
library;

import 'package:meta/meta.dart';

/// Everything the one rule needs to know about a single Request.
///
/// The counts are *active-attention* counts (the `clearedAt` axis U10b moved
/// the server onto), never read-axis `seen_at` acks.
@immutable
class RequestAttentionFacts {
  const RequestAttentionFacts({
    required this.requestId,
    this.unclearedOptionalEvents = 0,
    this.unclearedOutcomes = 0,
    this.liveObligations = 0,
    this.pendingForward = false,
    this.pendingPrompt = false,
    this.viewerArchived = false,
  });

  final String requestId;

  /// Uncleared optional events on this Request (§6 `request.dot`).
  final int unclearedOptionalEvents;

  /// Uncleared outcomes on this Request (§6 `request.dot`).
  final int unclearedOutcomes;

  /// Live obligation receipts (§6 `request.count`) — obligations, not cards.
  final int liveObligations;

  /// A forward awaiting the viewer's decision (§6 `for you.dot`).
  final bool pendingForward;

  /// A prompt awaiting the viewer's answer (§6 `for you.dot`).
  final bool pendingPrompt;

  /// Archived by the viewer: reachable only through the Archive filter.
  final bool viewerArchived;
}

/// §6 — `request.dot = has at least one uncleared optional event or outcome`.
bool requestHasDot(RequestAttentionFacts r) =>
    r.unclearedOptionalEvents > 0 || r.unclearedOutcomes > 0;

/// §6 — `request.count = number of live obligations on it`.
int requestCount(RequestAttentionFacts r) => r.liveObligations;

/// Something the viewer can act on. Dot **or** count — not one gating the other.
bool requestHasMyDeskAttention(RequestAttentionFacts r) =>
    requestHasDot(r) || requestCount(r) > 0;

/// §6 — `for you.dot = any dismissible attention, pending forward or prompt`.
bool requestHasForYouAttention(RequestAttentionFacts r) =>
    requestHasDot(r) || r.pendingForward || r.pendingPrompt;

/// The My Desk filter that can reach a Request. M1's reachability half: what is
/// counted must be *exposed by a filter the surface actually offers*.
enum MyDeskAttentionFilter { active, archive }

MyDeskAttentionFilter myDeskFilterExposing(RequestAttentionFacts r) =>
    r.viewerArchived
    ? MyDeskAttentionFilter.archive
    : MyDeskAttentionFilter.active;

/// Every My Desk filter this client ships. Archived attention contributes to
/// the dot **because** the Archive filter exposes it (§6); drop `archive` from
/// this set and the archived Requests stop being counted too — which is the
/// other half of the contract's "or it contributes to neither".
const myDeskExposedFilters = {
  MyDeskAttentionFilter.active,
  MyDeskAttentionFilter.archive,
};

/// **The** My Desk rule. The list renders these rows; the indicator counts
/// these rows. One function, two callers.
List<RequestAttentionFacts> myDeskAttentionMembers(
  Iterable<RequestAttentionFacts> requests, {
  Set<MyDeskAttentionFilter> exposedFilters = myDeskExposedFilters,
}) => [
  for (final r in requests)
    if (requestHasMyDeskAttention(r) &&
        exposedFilters.contains(myDeskFilterExposing(r)))
      r,
];

/// **The** For You rule, same shape.
List<RequestAttentionFacts> forYouAttentionMembers(
  Iterable<RequestAttentionFacts> requests,
) => [
  for (final r in requests)
    if (requestHasForYouAttention(r)) r,
];

/// A surface's two independent indicators.
@immutable
class SurfaceIndicators {
  const SurfaceIndicators({required this.dot, required this.count});

  final bool dot;

  /// `0` means no number. For You is always `0` — it never has a count (§6).
  final int count;

  bool get hasCount => count > 0;

  /// Anything at all is showing on the tab icon.
  bool get isLit => dot || hasCount;

  @override
  bool operator ==(Object other) =>
      other is SurfaceIndicators && other.dot == dot && other.count == count;

  @override
  int get hashCode => Object.hash(dot, count);

  @override
  String toString() => 'SurfaceIndicators(dot: $dot, count: $count)';
}

/// Indicators **from the membership list**, not from the facts. This signature
/// is the M1 guarantee: there is no input here that the list did not already
/// filter, so an indicator cannot light over rows the list excluded.
SurfaceIndicators indicatorsFromMembers(List<RequestAttentionFacts> members) =>
    SurfaceIndicators(
      dot: members.any(requestHasDot),
      count: members.fold(0, (sum, r) => sum + requestCount(r)),
    );

SurfaceIndicators myDeskIndicators(
  Iterable<RequestAttentionFacts> requests, {
  Set<MyDeskAttentionFilter> exposedFilters = myDeskExposedFilters,
}) => indicatorsFromMembers(
  myDeskAttentionMembers(requests, exposedFilters: exposedFilters),
);

/// For You: a dot, never a count (§6).
SurfaceIndicators forYouIndicators(Iterable<RequestAttentionFacts> requests) =>
    SurfaceIndicators(
      dot: forYouAttentionMembers(requests).isNotEmpty,
      count: 0,
    );

/// The same rule one level up, for surfaces whose membership the **server**
/// already filtered (U10b put the server's totals on this axis). A total is a
/// count of rows the authorized default list returns, so `> 0` here is the same
/// statement as `members.isNotEmpty` above.
bool surfaceDotFromTotal(int dotBearingTotal) => dotBearingTotal > 0;

/// The obligation number a surface shows, or `0` for none.
int surfaceCountFromTotal(int obligationTotal) =>
    obligationTotal > 0 ? obligationTotal : 0;
