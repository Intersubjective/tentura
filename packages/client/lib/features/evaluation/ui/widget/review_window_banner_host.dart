import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'review_banner.dart';

/// Presents review-window status from [BeaconViewState.reviewWindowInfo].
///
/// Author lifecycle ACTs (review contributions, close now) live in the HUD
/// action rail; this widget shows informational copy and non-author review CTAs.
class ReviewWindowBannerHost extends StatelessWidget {
  const ReviewWindowBannerHost({
    required this.reviewWindowInfo,
    this.isAuthor = false,
    super.key,
  });

  final ReviewWindowInfo? reviewWindowInfo;
  final bool isAuthor;

  static const _slotPadding = EdgeInsets.only(top: 10, bottom: 10);

  @override
  Widget build(BuildContext context) {
    final review = reviewWindowInfo;
    if (review == null) {
      return const Padding(
        padding: _slotPadding,
        child: LinearProgressIndicator(),
      );
    }
    if (!review.hasWindow || review.windowComplete) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (!isAuthor && review.viewerHasOutstandingReviewWork) {
      return Padding(
        padding: _slotPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewBanner(
              isDraftPhase: false,
              margin: EdgeInsets.zero,
              onPrimary: () => context.router.push(
                ReviewContributionsRoute(id: review.beaconId),
              ),
            ),
            if (review.closesAt != null && review.closesAt!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l10n.beaconReviewWindowClosesAt(review.closesAt!),
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    if (isAuthor &&
        !review.viewerHasOutstandingReviewWork &&
        review.canCloseNow != true) {
      return Padding(
        padding: _slotPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconHudWaitingForReviews,
              style: TenturaText.status(scheme.onSurfaceVariant),
            ),
            if (review.closesAt != null && review.closesAt!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l10n.beaconReviewWindowClosesAt(review.closesAt!),
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
