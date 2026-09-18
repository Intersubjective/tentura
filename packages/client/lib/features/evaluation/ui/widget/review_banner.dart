import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Inline banner: draft phase (open beacon) or review window after closure.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({
    required this.onPrimary,
    required this.isDraftPhase,
    this.margin,
    this.progressLine,
    super.key,
  });

  final VoidCallback onPrimary;

  /// True while beacon is open (draft review CTA only); false after closure (banner + submit).
  final bool isDraftPhase;

  /// Outer card margin; defaults to People-tab spacing when null.
  final EdgeInsetsGeometry? margin;

  /// Required-package progress, shown only while answers are incomplete.
  final String? progressLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    if (isDraftPhase) {
      return Padding(
        padding: const EdgeInsets.only(bottom: TenturaSpacing.section),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TenturaRadii.button),
              ),
            ),
            child: Text(l10n.evaluationBannerDraftReview),
          ),
        ),
      );
    }
    return Card(
      margin: margin ?? const EdgeInsets.only(bottom: TenturaSpacing.section),
      child: Padding(
        padding: TenturaSpacing.cardPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: onPrimary,
              child: Text(l10n.beaconHudActReviewContributions),
            ),
            if (progressLine != null) ...[
              SizedBox(height: tt.tightGap),
              Text(progressLine!, style: TenturaText.bodySmall(tt.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
