import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
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
    final closesAtLabel = _formatClosesAt(context, review.closesAt);
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
            if (closesAtLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                l10n.beaconReviewWindowClosesAt(closesAtLabel),
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
            if (closesAtLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                l10n.beaconReviewWindowClosesAt(closesAtLabel),
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
