import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The two indicators a Request card carries (D09, contract §6).
///
/// A dot iff the Request has at least one uncleared optional event or outcome;
/// a number iff it has live obligations. The two are **independent**: neither
/// slot is conditional on the other, so a Request with both shows both. Each
/// slot asks [requestHasDot] / [requestCount] — the same functions the surface
/// indicator and the surface's default list ask (M1), so a card cannot
/// disagree with the tab above it.
class RequestAttentionIndicators extends StatelessWidget {
  const RequestAttentionIndicators({required this.facts, super.key});

  static const dotKey = ValueKey('request-attention-dot');
  static const countKey = ValueKey('request-attention-count');

  /// Dot diameter; matches the nav [Badge] dot so the two read as one language.
  static const double dotDiameter = 8;

  final RequestAttentionFacts facts;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final showDot = requestHasDot(facts);
    final count = requestCount(facts);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDot)
          Semantics(
            key: dotKey,
            label: l10n.activityNavBadgeNewActivity,
            container: true,
            child: SizedBox(
              width: dotDiameter,
              height: dotDiameter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        if (showDot && count > 0) SizedBox(width: tt.rowGap),
        if (count > 0)
          Semantics(
            key: countKey,
            label: l10n.myWorkNavBadgeObligations(count),
            excludeSemantics: true,
            container: true,
            child: TenturaCountBadge(
              count: count,
              backgroundColor: scheme.primary,
            ),
          ),
      ],
    );
  }
}
