import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/forward_state.dart';

/// Underline tabs for forward recipient scopes.
class ForwardScopeLinks extends StatelessWidget {
  const ForwardScopeLinks({
    required this.activeFilter,
    required this.counts,
    required this.onScopeChanged,
    super.key,
  });

  final ForwardFilter activeFilter;
  final ForwardScopeCounts counts;
  final ValueChanged<ForwardFilter> onScopeChanged;

  /// Reserved height for the pinned scope bar.
  ///
  /// Uses the larger of [TenturaTokens.buttonHeight] and the intrinsic tab
  /// content (`2×rowGap` + scaled label line + `iconTextGap` + 2px underline)
  /// so a large system text scale cannot RenderFlex-overflow past the
  /// [SliverPersistentHeader] extent into the first list row's hit targets.
  static double preferredHeight(TenturaTokens tt, TextScaler textScaler) {
    // Dominant span in the tab label is bodySmall (13 @ height 1.35).
    const bodySmallFontSize = 13.0;
    const bodySmallHeight = 1.35;
    final lineHeight = textScaler.scale(bodySmallFontSize * bodySmallHeight);
    final contentHeight =
        2 * tt.rowGap + lineHeight + tt.iconTextGap + 2;
    return math.max(tt.buttonHeight, contentHeight);
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final height = preferredHeight(tt, MediaQuery.textScalerOf(context));

    Widget scopeTab(ForwardFilter f, String label, String hint, int count) {
      final active = f == activeFilter;
      final activeColor = tt.info;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          hint: hint,
          child: Tooltip(
            message: hint,
            child: InkWell(
              onTap: () => onScopeChanged(f),
              child: SizedBox.expand(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tt.iconTextGap,
                          vertical: tt.rowGap,
                        ),
                        child: Center(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: label,
                                  style: TenturaText.tabLabel(
                                    active ? activeColor : tt.textMuted,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ($count)',
                                  style: TenturaText.withTabular(
                                    TenturaText.bodySmall(
                                      active ? activeColor : tt.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: tt.iconTextGap),
                    SizedBox(
                      width: double.infinity,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: active ? activeColor : Colors.transparent,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(tt.tightGap / 2),
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tt.border)),
          ),
          child: Row(
            children: [
              scopeTab(
                ForwardFilter.unseen,
                l10n.forwardScopeUnseenShort,
                l10n.forwardScopeUnseenHint,
                counts.unseen,
              ),
              scopeTab(
                ForwardFilter.alreadyInvolved,
                l10n.forwardScopeInvolvedShort,
                l10n.forwardScopeInvolvedHint,
                counts.involved,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
