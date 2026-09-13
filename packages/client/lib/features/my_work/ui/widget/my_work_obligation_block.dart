import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';

const _kVisibleObligationLines = 3;

class MyWorkObligationBlock extends StatefulWidget {
  const MyWorkObligationBlock({
    required this.vm,
    required this.obligations,
    this.onReviewHelpOffers,
    this.onReviewContributions,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final List<AttentionReceipt> obligations;
  final VoidCallback? onReviewHelpOffers;
  final VoidCallback? onReviewContributions;

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
    final obligations = widget.obligations;
    final showReviewHelpOffers = widget.vm.showReviewHelpOffersCta;
    final showReview = widget.vm.showReviewCta;
    final primaryCtaLabel = showReviewHelpOffers
        ? l10n.myWorkReviewHelpOffersCta
        : showReview
        ? l10n.myWorkReviewCta
        : null;
    final primaryOnPressed = showReviewHelpOffers
        ? widget.onReviewHelpOffers
        : showReview
        ? widget.onReviewContributions
        : null;

    if (obligations.isEmpty && primaryCtaLabel == null) {
      return const SizedBox.shrink();
    }

    final visibleCount = _expanded
        ? obligations.length
        : obligations.length.clamp(0, _kVisibleObligationLines);
    final hiddenCount = obligations.length - _kVisibleObligationLines;

    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visibleCount; i++)
            _ObligationLine(
              receipt: obligations[i],
              onDone: () => unawaited(
                context.read<MyWorkCubit>().settleObligation(
                  widget.vm.beaconId,
                  obligations[i].id,
                ),
              ),
            ),
          if (!_expanded && hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TenturaTextAction(
                label: l10n.myWorkObligationMore(hiddenCount),
                tone: TenturaTone.neutral,
                onPressed: () => setState(() => _expanded = true),
              ),
            ),
          if (primaryCtaLabel != null && primaryOnPressed != null) ...[
            SizedBox(height: tt.tightGap),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: primaryOnPressed,
                style: FilledButton.styleFrom(
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
      ),
    );
  }
}

class _ObligationLine extends StatelessWidget {
  const _ObligationLine({
    required this.receipt,
    required this.onDone,
  });

  final AttentionReceipt receipt;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
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

    return Semantics(
      identifier: TestIds.myWorkObligation(receipt.id),
      child: Padding(
        padding: EdgeInsets.only(bottom: tt.tightGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: bodyStyle,
                  children: [
                    if (actorLabel.isNotEmpty) ...[
                      TextSpan(
                        text: actorLabel,
                        style: bodyStyle.copyWith(fontWeight: FontWeight.w500),
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
            SizedBox(width: tt.iconTextGap),
            TenturaTextAction(
              label: l10n.myWorkObligationDone,
              tone: TenturaTone.neutral,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
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
