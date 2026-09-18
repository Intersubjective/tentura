import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'review_banner.dart';

/// [ReviewWindowInfo.closesAt] is a raw server ISO string, not a [DateTime]
/// — format it the same way `review_contributions_screen.dart` does instead
/// of interpolating the raw wire value (issue #112).
String? _formatClosesAt(BuildContext context, String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateFormat.yMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(parsed.toLocal());
}

/// Presents review-window status from `BeaconViewState.reviewWindowInfo`.
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

  static const _slotPadding = EdgeInsets.symmetric(
    vertical: TenturaSpacing.cardGap,
  );

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
    final tt = context.tt;
    final closesAtLabel = _formatClosesAt(context, review.closesAt);
    final scheme = Theme.of(context).colorScheme;
    final package = reviewPackageStateFromWindow(review);
    void openReview() {
      unawaited(
        context.router.push(ReviewContributionsRoute(id: review.beaconId)),
      );
    }

    final Widget content;
    switch (package) {
      case ReviewPackageState.inProgress:
      case ReviewPackageState.readyToSend:
      case ReviewPackageState.changedNotSent:
        // The author's HUD owns the single primary ACT, including close-now.
        if (isAuthor) return const SizedBox.shrink();
        content = ReviewBanner(
          isDraftPhase: false,
          margin: EdgeInsets.zero,
          onPrimary: openReview,
          progressLine: package == ReviewPackageState.inProgress
              ? l10n.beaconHudActEffectReviewProgress(
                  review.requiredTotal - review.requiredReviewed,
                  review.requiredTotal,
                )
              : null,
        );
      case ReviewPackageState.sent:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconHudReviewSent,
              style: TenturaText.status(scheme.onSurfaceVariant),
            ),
            if (!isAuthor || !review.allRequiredSent) ...[
              SizedBox(height: tt.tightGap),
              Text(
                isAuthor
                    ? l10n.beaconHudWaitingForRequiredReviews
                    : l10n.beaconHudWaitingForAuthorClose,
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
            ],
            TextButton(
              onPressed: openReview,
              child: Text(l10n.beaconHudReviewEdit),
            ),
          ],
        );
      case ReviewPackageState.paused:
      case ReviewPackageState.closed:
      case ReviewPackageState.closedUnsent:
      case ReviewPackageState.notEnrolled:
      case ReviewPackageState.empty:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: _slotPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (closesAtLabel != null) ...[
            SizedBox(height: tt.rowGap),
            Text(
              l10n.beaconReviewWindowClosesAt(closesAtLabel),
              style: TenturaText.status(scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
