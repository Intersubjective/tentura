import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/group_my_work_obligations.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_plan_step_rows.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const kMyWorkVisibleObligationGroups = 3;

/// Whether the active-event block should render (rows and/or fallback CTA).
bool myWorkObligationBlockVisible({
  required MyWorkCardViewModel vm,
  required List<AttentionReceipt> obligations,
  List<AttentionReceipt> optionalEvents = const [],
  bool suppressReviewHelpOffersFallback = false,
  bool hasPlanRows = false,
}) {
  if (hasPlanRows) return true;
  if (obligations.isNotEmpty) return true;
  if (optionalEvents.isNotEmpty) return true;
  if (vm.showReviewHelpOffersCta && !suppressReviewHelpOffersFallback) {
    return true;
  }
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
    this.onRespondHelpOffer,
    this.suppressReviewHelpOffersFallback = false,
    this.planRows,
    super.key,
  });

  /// The Request plan rows (#220 §5.8), rendered first.
  final MyWorkPlanStepRows? planRows;

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

  /// Opens the People help-offer sheet for [offererId].
  final void Function(String offererId)? onRespondHelpOffer;

  /// When true, do not show the aggregate Review-offers tonal CTA (footer
  /// already provides that destination).
  final bool suppressReviewHelpOffersFallback;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    // Help offers lead, so the one «Предложили помощь · N» header sits right
    // above the rows it names; the rest keep their server order.
    final grouped = groupMyWorkObligations(obligations);
    final groups = [
      ...grouped.where((g) => g.isHelpOffer),
      ...grouped.where((g) => !g.isHelpOffer),
    ];
    final helpOfferIds = {
      for (final g in groups)
        if (g.isHelpOffer && _respondCallback(g) != null) g.primary.id,
    };
    final groupByReceiptId = <String, MyWorkObligationGroup>{
      for (final group in groups) group.primary.id: group,
    };

    // Aggregate Review offers (People list) is a different destination from
    // per-offer Respond sheet — keep when CTA flag is set unless footer owns it.
    final showAggregateReviewOffers =
        vm.showReviewHelpOffersCta && !suppressReviewHelpOffersFallback;

    final rows = <AttentionReceipt>[
      for (final group in groups) group.primary,
      ...optionalEvents,
    ];

    final planRows = this.planRows;
    if (rows.isEmpty && !showAggregateReviewOffers && planRows == null) {
      return const SizedBox.shrink();
    }

    final primaryCtaLabel = showAggregateReviewOffers
        ? l10n.myWorkReviewHelpOffersCta
        : null;
    final primaryOnPressed = showAggregateReviewOffers
        ? onReviewHelpOffers
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
        if (planRows != null) ...[
          planRows,
          if (rows.isNotEmpty || showAggregateReviewOffers)
            SizedBox(height: tt.rowGap),
        ],
        if (helpOfferIds.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Text(
              l10n.myWorkHelpOffersHeader(helpOfferIds.length),
              style: TenturaText.labelMedium(tt.textMuted),
            ),
          ),
        if (rows.isNotEmpty)
          ActivityEventSubcardBlock(
            eventTotal: groups.length + optionalTotal,
            eventsPreview: rows,
            visibleCap: visibleCap,
            beaconId: vm.beaconId,
            requestTitle: vm.beacon.title,
            // Offers made through the participant path show up only among
            // admitted helpers; without them the row fell back to an
            // anonymous "Help offered" (UI review #202).
            actors: {
              for (final user in vm.beacon.admittedHelperUsers) user.id: user,
              for (final user in vm.beacon.helpOfferUsers) user.id: user,
            },
            // §5: an obligation is not privately dismissible.
            canDismiss: attentionRowIsDismissible,
            onClearEvent: onClearEvent,
            onOpenTimeline: onOpenTimeline,
            quotedBodyOf: (receipt) => _quotedBody(l10n, receipt),
            // The header names the event; each offer row is the person, the
            // age and «Ответить» on one line.
            nameOnlyOf: (receipt) => helpOfferIds.contains(receipt.id),
            // Every obligation's CTA ends its own line — one row, one act —
            // instead of a link floating under it on its own left edge.
            trailingBuilder: (receipt) => _obligationCta(
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

  /// The per-kind CTA at the end of an obligation row. Every one of them
  /// opens a sheet or a flow that captures a choice or an input — that is what
  /// makes the row an obligation rather than an optional update (D04).
  ///
  /// Tonal, because answering is what the card is asking of you.
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
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: Size(0, tt.buttonHeight),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: EdgeInsets.symmetric(horizontal: tt.rowGap),
        ),
        child: Text(label),
      ),
    );
  }

  VoidCallback? _respondCallback(MyWorkObligationGroup group) {
    final offererId = group.offererId;
    final respond = onRespondHelpOffer;
    if (offererId == null || respond == null) return null;
    return () => respond(offererId);
  }

  String? _ctaLabel(L10n l10n, MyWorkObligationGroup group) {
    if (group.isHelpOffer) {
      return onRespondHelpOffer == null || group.offererId == null
          ? null
          : l10n.myWorkObligationRespond;
    }
    return null;
  }

  VoidCallback? _ctaCallback(MyWorkObligationGroup group) {
    if (group.isHelpOffer) return _respondCallback(group);
    return null;
  }
}
