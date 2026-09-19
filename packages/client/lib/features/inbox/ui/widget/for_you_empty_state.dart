import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
ForYouEmptyKind forYouEmptyKind({
  required bool hasActiveFilter,
  required bool hasPinnedZone,
}) {
  if (hasActiveFilter) return ForYouEmptyKind.noMatch;
  return hasPinnedZone
      ? ForYouEmptyKind.nothingNew
      : ForYouEmptyKind.nothingHere;
}

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

/// The empty For You stream, in whichever of §4's three voices applies.
class ForYouEmptyState extends StatelessWidget {
  const ForYouEmptyState({required this.kind, super.key});

  static const titleKey = Key('for-you-empty-title');
  static const hintKey = Key('for-you-empty-hint');

  final ForYouEmptyKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
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
