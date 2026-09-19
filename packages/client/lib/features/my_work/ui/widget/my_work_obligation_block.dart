import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/group_my_work_obligations.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const kMyWorkVisibleObligationGroups = 3;

/// Whether the active-event block should render (rows and/or fallback CTA).
bool myWorkObligationBlockVisible({
  required MyWorkCardViewModel vm,
  required List<AttentionReceipt> obligations,
  List<AttentionReceipt> optionalEvents = const [],
  bool suppressReviewHelpOffersFallback = false,
  bool suppressReviewFallback = false,
}) {
  if (obligations.isNotEmpty) return true;
  if (optionalEvents.isNotEmpty) return true;
  if (vm.showReviewHelpOffersCta && !suppressReviewHelpOffersFallback) {
    return true;
  }
  if (vm.showReviewCta && !suppressReviewFallback) return true;
  return false;
}

/// My Desk's mounting of the shared active-event block (U14b).
///
/// One list per Request: obligations first, then the coalesced optional lines.
/// Obligation rows carry a decision-capturing CTA and **no** × (§5 — a private
/// dismissal would lie to whoever is waiting); optional rows carry the × and
/// no CTA. There is no generic Done: nothing in the product can be honestly
/// resolved by acknowledgment (D04, owner decision C), and the server refuses
/// the mutation that used to back it (U07b2).
class MyWorkObligationBlock extends StatelessWidget {
  const MyWorkObligationBlock({
    required this.vm,
    required this.obligations,
    this.optionalEvents = const [],
    this.optionalTotal = 0,
    this.onClearEvent,
    this.onOpenTimeline,
    this.onReviewHelpOffers,
    this.onReviewContributions,
    this.onRespondHelpOffer,
    this.suppressReviewHelpOffersFallback = false,
    this.suppressReviewFallback = false,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final List<AttentionReceipt> obligations;

  /// Uncleared optional events already in hand (the card's preview).
  final List<AttentionReceipt> optionalEvents;

  /// The server's count of uncleared optional events — never the loaded rows.
  final int optionalTotal;

  /// Clears one optional event (the clear axis, D02/U10b) — never `markSeen`.
  final ValueChanged<String>? onClearEvent;

  final VoidCallback? onOpenTimeline;
  final VoidCallback? onReviewHelpOffers;
  final VoidCallback? onReviewContributions;

  /// Opens the People help-offer sheet for [offererId].
  final void Function(String offererId)? onRespondHelpOffer;

  /// When true, do not show the aggregate Review-offers tonal CTA (footer
  /// already provides that destination).
  final bool suppressReviewHelpOffersFallback;

  /// When true, do not show the Review tonal CTA (footer / sub-card already
  /// provides ReviewContributionsRoute).
  final bool suppressReviewFallback;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final groups = groupMyWorkObligations(obligations);
    final hasReviewGroup = groups.any((g) => g.isReview);
    final groupByReceiptId = <String, MyWorkObligationGroup>{
      for (final group in groups) group.primary.id: group,
    };

    // Aggregate Review offers (People list) is a different destination from
    // per-offer Respond sheet — keep when CTA flag is set unless footer owns it.
    final showAggregateReviewOffers =
        vm.showReviewHelpOffersCta && !suppressReviewHelpOffersFallback;
    final showReviewFallback =
        vm.showReviewCta && !suppressReviewFallback && !hasReviewGroup;

    final rows = <AttentionReceipt>[
      for (final group in groups) group.primary,
      ...optionalEvents,
    ];

    if (rows.isEmpty && !showAggregateReviewOffers && !showReviewFallback) {
      return const SizedBox.shrink();
    }

    final primaryCtaLabel = showAggregateReviewOffers
        ? l10n.myWorkReviewHelpOffersCta
        : showReviewFallback
        ? (vm.reviewPackageState == ReviewPackageState.changedNotSent
              ? l10n.evaluationSubmitChanges
              : l10n.myWorkReviewCta)
        : null;
    final primaryOnPressed = showAggregateReviewOffers
        ? onReviewHelpOffers
        : showReviewFallback
        ? onReviewContributions
        : null;

    // Obligations up to the group cap, plus one optional line — so the × is
    // reachable in the collapsed state without expanding or navigating.
    final visibleCap =
        math.min(groups.length, kMyWorkVisibleObligationGroups) +
        (optionalEvents.isEmpty ? 0 : 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          ActivityEventSubcardBlock(
            eventTotal: groups.length + optionalTotal,
            eventsPreview: rows,
            visibleCap: visibleCap,
            beaconId: vm.beaconId,
            actors: {
              for (final user in vm.beacon.helpOfferUsers) user.id: user,
            },
            onClearEvent: onClearEvent,
            onOpenTimeline: onOpenTimeline,
            quotedBodyOf: (receipt) => _quotedBody(l10n, receipt),
            ctaBuilder: (receipt) => _obligationCta(
              context,
              l10n: l10n,
              group: groupByReceiptId[receipt.id],
            ),
          ),
        if (primaryCtaLabel != null && primaryOnPressed != null) ...[
          if (rows.isNotEmpty) SizedBox(height: tt.tightGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: primaryOnPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinInteractiveDimension),
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.cardGap,
                ),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(primaryCtaLabel),
            ),
          ),
        ],
      ],
    );
  }

  /// The event line names the actor; the message itself belongs behind the
  /// quote rule (§7). Returns null when the two would read the same.
  String? _quotedBody(L10n l10n, AttentionReceipt receipt) {
    final copy = resolveUpdatesFeedRowCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
      l10n: l10n,
    );
    final headline = copy.headline.trim();
    final body = copy.body.trim();
    if (body.isEmpty || body == headline) return null;
    return body;
  }

  /// The per-kind CTA under an obligation row. Every one of them opens a sheet
  /// or a flow that captures a choice or an input — that is what makes the row
  /// an obligation rather than an optional update (D04).
  Widget? _obligationCta(
    BuildContext context, {
    required L10n l10n,
    required MyWorkObligationGroup? group,
  }) {
    if (group == null) return null;
    final tt = context.tt;
    final label = _ctaLabel(l10n, group);
    final onPressed = _ctaCallback(group);
    if (label == null || onPressed == null) return null;
    return Semantics(
      identifier: TestIds.myWorkObligation(group.primary.id),
      child: Padding(
        padding: EdgeInsets.only(left: tt.cardGap),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TenturaTextAction(
            label: label,
            minInteractive: true,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  /// A review obligation the viewer has already opened by deep link and left
  /// a draft behind reads as in progress — opening a CTA and saving an unsent
  /// draft resolves nothing, so the obligation stays and says so (D04).
  String? _ctaLabel(L10n l10n, MyWorkObligationGroup group) {
    if (group.isHelpOffer) {
      return onRespondHelpOffer == null || group.offererId == null
          ? null
          : l10n.myWorkObligationRespond;
    }
    if (group.isReview) {
      if (onReviewContributions == null) return null;
      return switch (vm.reviewPackageState) {
        ReviewPackageState.changedNotSent => l10n.evaluationSubmitChanges,
        ReviewPackageState.readyToSend => l10n.evaluationSubmitFinish,
        ReviewPackageState.inProgress => l10n.evaluationBannerDraftReview,
        _ => l10n.myWorkReviewCta,
      };
    }
    return null;
  }

  VoidCallback? _ctaCallback(MyWorkObligationGroup group) {
    if (group.isHelpOffer) {
      final offererId = group.offererId;
      final respond = onRespondHelpOffer;
      if (offererId == null || respond == null) return null;
      return () => respond(offererId);
    }
    if (group.isReview) return onReviewContributions;
    return null;
  }
}
