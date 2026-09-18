import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';

enum MyWorkReviewAffordanceKind { none, primary, sent }

/// Review affordance shape on a My Work card, driven by the viewer's package
/// state (#162): a sent package is never offered again as a primary action.
MyWorkReviewAffordanceKind myWorkReviewAffordanceKind(
  ReviewPackageState? package,
) => switch (package) {
  ReviewPackageState.inProgress ||
  ReviewPackageState.readyToSend ||
  ReviewPackageState.changedNotSent => MyWorkReviewAffordanceKind.primary,
  ReviewPackageState.sent => MyWorkReviewAffordanceKind.sent,
  _ => MyWorkReviewAffordanceKind.none,
};

/// Card footer review block: filled primary while the package needs work,
/// status + demoted edit once sent, nothing otherwise.
class MyWorkReviewAffordance extends StatelessWidget {
  const MyWorkReviewAffordance({
    required this.vm,
    required this.isAuthor,
    required this.onOpenReview,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final bool isAuthor;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final package = vm.reviewPackageState;
    switch (myWorkReviewAffordanceKind(package)) {
      case MyWorkReviewAffordanceKind.none:
        return const SizedBox.shrink();
      case MyWorkReviewAffordanceKind.primary:
        return Align(
          alignment: Alignment.centerRight,
          child: TenturaCommandButton(
            label: package == ReviewPackageState.changedNotSent
                ? l10n.evaluationSubmitChanges
                : l10n.beaconHudActReviewContributions,
            onPressed: onOpenReview,
          ),
        );
      case MyWorkReviewAffordanceKind.sent:
        final tt = context.tt;
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.beaconHudReviewSent, style: TenturaText.status(muted)),
            if (!isAuthor || !vm.reviewAllRequiredSent) ...[
              SizedBox(height: tt.tightGap),
              Text(
                isAuthor
                    ? l10n.beaconHudWaitingForRequiredReviews
                    : l10n.beaconHudWaitingForAuthorClose,
                style: TenturaText.status(muted),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onOpenReview,
                child: Text(l10n.beaconHudReviewEdit),
              ),
            ),
          ],
        );
    }
  }
}
