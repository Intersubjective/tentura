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

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;

    Widget scopeTab(ForwardFilter f, String label, int count) {
      final active = f == activeFilter;
      final activeColor = tt.info;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: InkWell(
            onTap: () => onScopeChanged(f),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: tt.buttonHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: tt.iconTextGap),
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
                              text: '/$count',
                              style: TenturaText.withTabular(
                                TenturaText.bodySmall(tt.textFaint),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: tt.iconTextGap),
                    SizedBox(
                      width: double.infinity,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: active ? activeColor : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(1),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                  counts.unseen,
                ),
                scopeTab(
                  ForwardFilter.alreadyInvolved,
                  l10n.forwardScopeInvolvedShort,
                  counts.involved,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
