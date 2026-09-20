import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';

/// U16c-1 — the three ways For You can be empty, which
/// `docs/features/request-attention.md` §4 requires to **read differently**.
///
/// One empty state reused for all three is the defect §4 names. The three are
/// not shades of the same sentence: *nothing here* says the surface has never
/// carried anything, *nothing new* says the person cleared it, and *nothing
/// matching this filter* says the content is there but hidden.
enum ForYouEmptyKind {
  /// Nothing has ever been on this surface.
  nothingHere,

  /// Cleared — **and the decision zone may still be there**.
  ///
  /// This is the state *Dismiss all* produces. Owner decision A means the
  /// sweep never answers anybody, so an unanswered forward survives it, and
  /// the copy must therefore not claim an empty screen: §4's _Avoid_ line
  /// forbids celebrating "all clear" while decisions are pending.
  nothingNew,

  /// There is content; this filter does not show it.
  noMatch;

  String title(L10n l10n) => switch (this) {
    ForYouEmptyKind.nothingHere => l10n.forYouEmptyNothingHere,
    ForYouEmptyKind.nothingNew => l10n.forYouEmptyNothingNew,
    ForYouEmptyKind.noMatch => l10n.forYouEmptyNoMatch,
  };

  String hint(L10n l10n) => switch (this) {
    ForYouEmptyKind.nothingHere => l10n.forYouEmptyNothingHereHint,
    ForYouEmptyKind.nothingNew => l10n.forYouEmptyNothingNewHint,
    ForYouEmptyKind.noMatch => l10n.forYouEmptyNoMatchHint,
  };
}

/// Which of §4's three empty states this surface is in.
///
/// A pure function, so the rule is testable without laying anything out, and
/// so the copy and the condition can never be chosen in two different places.
///
/// The pinned zone is the discriminator between *nothing here* and *nothing
/// new*, and that is exactly §4's own wording: "Because Dismiss all leaves
/// decisions alone, a cleared For you can still show its pinned zone."
/// U17d extends it with the other way a surface can be known to have been
/// cleared: the person swept it in this session. Without that input the
/// sweep that empties For You *and* its pinned zone lands on "Nothing here
/// yet" — telling somebody who just cleared five rows that nothing was ever
/// here. The rule stays one function (M1); it gained a second true case.
ForYouEmptyKind forYouEmptyKind({
  required bool hasActiveFilter,
  required bool hasPinnedZone,
  bool wasClearedHere = false,
}) {
  if (hasActiveFilter) return ForYouEmptyKind.noMatch;
  return hasPinnedZone || wasClearedHere
      ? ForYouEmptyKind.nothingNew
      : ForYouEmptyKind.nothingHere;
}

/// Did an explicit sweep in this session clear anything off this surface?
///
/// Deliberately true for a *partial* sweep as well: it cleared rows, so the
/// surface is "nothing new" rather than "nothing here". Whether that state
/// may celebrate is [forYouCaughtUpReward]'s separate question.
bool forYouSweptHere(AttentionDismissAllResult? lastSweep) =>
    lastSweep != null && lastSweep.appliedCount > 0;

/// May an empty state be shown at all?
///
/// A pure predicate rather than a condition inlined in the sliver list,
/// because it is the place §4's _Avoid_ line applies: "celebrating 'all
/// clear' … while loading, offline, or after a partial sweep". An empty list
/// and a list that has not arrived — or failed to — are different facts, and a
/// spinner replaced by "nothing new" is the failure. Inlined, that distinction
/// is a boolean nobody can test without a whole screen.
bool shouldShowForYouEmptyState({
  required bool hasRows,
  required bool isLoading,
  required bool hasError,
}) => !hasRows && !isLoading && !hasError;

/// U17d / D18 — may this cleared surface present itself as a *reward*, and
/// with what number?
///
/// Returns `null` when the empty state must stay plain. The reward is a
/// presentation of [ForYouEmptyKind.nothingNew] and of nothing else: *nothing
/// here* has no completed attention to celebrate and *nothing matching this
/// filter* is a hidden surface, not a cleared one.
///
/// [lastSweep] is the last explicit *Dismiss all* of this session, or `null`
/// if the person never ran one — a surface cleared by opening Requests is
/// still caught up, it just has no number, and inventing one is the
/// fabricated success D18 forbids.
///
/// A sweep that did not finish — bounded and resumable, or with members the
/// server failed to clear — withdraws the reward entirely. "Never celebrate
/// after a partial sweep" is a rule about the celebration, not only about the
/// count.
ForYouCaughtUpReward? forYouCaughtUpReward({
  required ForYouEmptyKind kind,
  AttentionDismissAllResult? lastSweep,
}) {
  if (kind != ForYouEmptyKind.nothingNew) return null;
  if (lastSweep == null) return const ForYouCaughtUpReward();
  if (!lastSweep.isComplete || lastSweep.failed.isNotEmpty) return null;
  return ForYouCaughtUpReward(
    clearedCount: lastSweep.appliedCount > 0 ? lastSweep.appliedCount : null,
  );
}

/// The reward, and the number it may state. A `null` [clearedCount] is a
/// caught-up surface with no explicit sweep behind it.
class ForYouCaughtUpReward {
  const ForYouCaughtUpReward({this.clearedCount});

  final int? clearedCount;
}

/// The empty For You stream, in whichever of §4's three voices applies.
class ForYouEmptyState extends StatelessWidget {
  const ForYouEmptyState({required this.kind, this.lastSweep, super.key});

  static const titleKey = Key('for-you-empty-title');
  static const hintKey = Key('for-you-empty-hint');

  final ForYouEmptyKind kind;

  /// The last explicit sweep of this session, if any (D18).
  final AttentionDismissAllResult? lastSweep;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final reward = forYouCaughtUpReward(kind: kind, lastSweep: lastSweep);
    // D18 — the cleared state is rewarded, the other two are stated. The
    // rule that picks between them is `forYouCaughtUpReward`, so this widget
    // holds no second copy of it.
    if (reward != null) {
      final cleared = reward.clearedCount;
      return CaughtUpPanel(
        title: kind.title(l10n),
        detail: kind.hint(l10n),
        clearedLabel: cleared == null
            ? null
            : l10n.inboxDismissAllCleared(cleared),
      );
    }
    return Semantics(
      container: true,
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kind.title(l10n),
              key: titleKey,
              textAlign: TextAlign.center,
              style: TenturaText.title(tt.text),
            ),
            SizedBox(height: tt.tightGap),
            // Deliberately unclipped and unellipsised: the sentence that
            // explains why the decision zone is still above is the one part of
            // this state that must not be the part that gets truncated.
            Text(
              kind.hint(l10n),
              key: hintKey,
              textAlign: TextAlign.center,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
