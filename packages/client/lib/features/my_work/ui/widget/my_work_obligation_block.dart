import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/group_my_work_obligations.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';

const kMyWorkVisibleObligationGroups = 3;

/// Whether the obligation block should render (sub-cards and/or fallback CTA).
bool myWorkObligationBlockVisible({
  required MyWorkCardViewModel vm,
  required List<AttentionReceipt> obligations,
  bool suppressReviewHelpOffersFallback = false,
  bool suppressReviewFallback = false,
}) {
  if (obligations.isNotEmpty) return true;
  if (vm.showReviewHelpOffersCta && !suppressReviewHelpOffersFallback) {
    return true;
  }
  if (vm.showReviewCta && !suppressReviewFallback) return true;
  return false;
}

class MyWorkObligationBlock extends StatefulWidget {
  const MyWorkObligationBlock({
    required this.vm,
    required this.obligations,
    this.onReviewHelpOffers,
    this.onReviewContributions,
    this.onRespondHelpOffer,
    this.suppressReviewHelpOffersFallback = false,
    this.suppressReviewFallback = false,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final List<AttentionReceipt> obligations;
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
  State<MyWorkObligationBlock> createState() => _MyWorkObligationBlockState();
}

class _MyWorkObligationBlockState extends State<MyWorkObligationBlock> {
  bool _expanded = false;
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final groups = groupMyWorkObligations(widget.obligations);
    final hasReviewGroup = groups.any((g) => g.isReview);

    // Aggregate Review offers (People list) is a different destination from
    // per-offer Respond sheet — keep when CTA flag is set unless footer owns it.
    final showAggregateReviewOffers =
        widget.vm.showReviewHelpOffersCta &&
        !widget.suppressReviewHelpOffersFallback;
    final showReviewFallback =
        widget.vm.showReviewCta &&
        !widget.suppressReviewFallback &&
        !hasReviewGroup;

    if (groups.isEmpty &&
        !showAggregateReviewOffers &&
        !showReviewFallback) {
      return const SizedBox.shrink();
    }

    final visibleCount = _expanded
        ? groups.length
        : groups.length.clamp(0, kMyWorkVisibleObligationGroups);
    final hiddenCount = groups.length - kMyWorkVisibleObligationGroups;

    final primaryCtaLabel = showAggregateReviewOffers
        ? l10n.myWorkReviewHelpOffersCta
        : showReviewFallback
        ? l10n.myWorkReviewCta
        : null;
    final primaryOnPressed = showAggregateReviewOffers
        ? widget.onReviewHelpOffers
        : showReviewFallback
        ? widget.onReviewContributions
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleCount; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i < visibleCount - 1 || hiddenCount > 0 || primaryCtaLabel != null
                  ? tt.tightGap
                  : 0,
            ),
            child: _ObligationSubCard(
              vm: widget.vm,
              group: groups[i],
              onRespond: groups[i].isHelpOffer &&
                      groups[i].offererId != null &&
                      widget.onRespondHelpOffer != null
                  ? () => widget.onRespondHelpOffer!(groups[i].offererId!)
                  : null,
              onReview: groups[i].isReview && widget.onReviewContributions != null
                  ? widget.onReviewContributions
                  : null,
              onDone: () => unawaited(
                context.read<MyWorkCubit>().settleObligations(
                  widget.vm.beaconId,
                  groups[i].receiptIds,
                ),
              ),
            ),
          ),
        if (!_expanded && hiddenCount > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TenturaTextAction(
              label: l10n.myWorkObligationMore(hiddenCount),
              tone: TenturaTone.neutral,
              minInteractive: true,
              onPressed: () => setState(() => _expanded = true),
            ),
          ),
        if (primaryCtaLabel != null && primaryOnPressed != null) ...[
          if (groups.isNotEmpty || (!_expanded && hiddenCount > 0))
            SizedBox(height: tt.tightGap),
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
}

class _ObligationSubCard extends StatelessWidget {
  const _ObligationSubCard({
    required this.vm,
    required this.group,
    required this.onDone,
    this.onRespond,
    this.onReview,
  });

  final MyWorkCardViewModel vm;
  final MyWorkObligationGroup group;
  final VoidCallback onDone;
  final VoidCallback? onRespond;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final receipt = group.primary;
    final copy = resolveUpdatesFeedRowCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
      l10n: l10n,
    );
    final actorLabel = _obligationActorLabel(receipt);
    final eventCopy = _obligationEventCopy(copy, actorLabel: actorLabel);
    final age = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final muted = scheme.onSurfaceVariant;
    final bodyStyle = TenturaText.bodySmall(muted);
    final ageStyle = TenturaText.withTabular(TenturaText.bodySmall(tt.textFaint));
    final profile = _matchingHelpOfferUser(vm, group.offererId);

    return Semantics(
      identifier: TestIds.myWorkObligation(receipt.id),
      child: TenturaTechCardStatic(
        surfaceOverride: tt.bg,
        borderOverride: tt.borderSubtle,
        radius: TenturaRadii.cardDense,
        padding: EdgeInsets.all(tt.cardGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ObligationAvatar(profile: profile, label: actorLabel),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: bodyStyle,
                      children: [
                        if (actorLabel.isNotEmpty) ...[
                          TextSpan(
                            text: actorLabel,
                            style: bodyStyle.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: ' · ',
                            style: bodyStyle.copyWith(
                              color: muted.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                        TextSpan(text: eventCopy),
                        TextSpan(text: ' · ', style: ageStyle),
                        TextSpan(text: age, style: ageStyle),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: tt.tightGap),
            Wrap(
              spacing: tt.iconTextGap,
              runSpacing: tt.tightGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onRespond != null)
                  TenturaTextAction(
                    label: l10n.myWorkObligationRespond,
                    tone: TenturaTone.info,
                    minInteractive: true,
                    onPressed: onRespond,
                  ),
                if (onReview != null)
                  TenturaTextAction(
                    label: l10n.myWorkReviewCta,
                    tone: TenturaTone.info,
                    minInteractive: true,
                    onPressed: onReview,
                  ),
                TenturaTextAction(
                  label: l10n.myWorkObligationDone,
                  tone: TenturaTone.neutral,
                  minInteractive: true,
                  semanticsIdentifier: TestIds.myWorkObligationDone(
                    receipt.id,
                  ),
                  onPressed: onDone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ObligationAvatar extends StatelessWidget {
  const _ObligationAvatar({
    required this.profile,
    required this.label,
  });

  final Profile? profile;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (profile != null) {
      return TenturaAvatar.small(profile: profile!);
    }
    final initials = label.isNotEmpty
        ? label.characters.take(2).toString().toUpperCase()
        : '?';
    final tt = context.tt;
    final size = tt.metadataAvatarSize;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TenturaText.status(
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Profile? _matchingHelpOfferUser(MyWorkCardViewModel vm, String? offererId) {
  if (offererId == null || offererId.isEmpty) return null;
  for (final user in vm.beacon.helpOfferUsers) {
    if (user.id == offererId) return user;
  }
  return null;
}

String _obligationActorLabel(AttentionReceipt receipt) {
  final title = receipt.title.trim();
  if (title.isEmpty) {
    return '';
  }
  return switch (receipt.presentationKey) {
    'help_offer_submitted' ||
    'offer_accepted' ||
    'room_message_posted' ||
    'needs_me' ||
    'blocker_opened' ||
    'promise_made' =>
      title.split(RegExp(r'\s+')).first,
    _ => '',
  };
}

String _obligationEventCopy(
  UpdatesFeedRowCopy copy, {
  required String actorLabel,
}) {
  final headline = copy.headline.trim();
  final body = copy.body.trim();
  if (actorLabel.isNotEmpty && headline == actorLabel && body.isNotEmpty) {
    return body;
  }
  if (headline.isNotEmpty) {
    return headline;
  }
  return body;
}
