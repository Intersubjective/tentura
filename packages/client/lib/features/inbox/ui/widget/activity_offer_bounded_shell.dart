import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Shared bounded offer-card chrome (design §5.1): avatar, headline, why, age, ✕.
class ActivityOfferBoundedShell extends StatelessWidget {
  const ActivityOfferBoundedShell({
    required this.leading,
    required this.headline,
    required this.whyLine,
    required this.createdAt,
    required this.showUnseenDot,
    required this.onBodyTap,
    this.onDismiss,
    this.footer,
    super.key,
  });

  final Widget leading;
  final String headline;
  final String whyLine;
  final DateTime createdAt;
  final bool showUnseenDot;
  final VoidCallback onBodyTap;
  final VoidCallback? onDismiss;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final localCreatedAt = createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tt.rowGap,
          tt.tightGap,
          tt.tightGap,
          tt.tightGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onDismiss != null)
                  Semantics(
                    button: true,
                    label: l10n.inboxDismissTooltip,
                    child: IconButton(
                      key: TestIds.key(TestIds.inboxDismiss),
                      onPressed: onDismiss,
                      icon: Icon(Icons.close, size: tt.iconSize),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                Expanded(
                  child: InkWell(
                    onTap: onBodyTap,
                    borderRadius: BorderRadius.circular(tt.cardRadius),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: tt.tightGap,
                        right: tt.tightGap,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          leading,
                          SizedBox(width: tt.avatarTextGap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        headline,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TenturaText.titleSmall(
                                          scheme.onSurface,
                                        ).copyWith(
                                          fontWeight: showUnseenDot
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (showUnseenDot) ...[
                                      SizedBox(width: tt.iconTextGap),
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: tt.info,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.surfaceContainerLow,
                                            width: tt.tightGap,
                                          ),
                                        ),
                                        child: SizedBox.square(
                                          dimension: tt.unreadDotSize,
                                        ),
                                      ),
                                    ],
                                    SizedBox(width: tt.iconTextGap),
                                    Tooltip(
                                      message: absoluteTime,
                                      child: Text(
                                        ageLabel,
                                        style: TenturaText.withTabular(
                                          TenturaText.bodySmall(tt.textFaint),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (whyLine.isNotEmpty) ...[
                                  SizedBox(height: tt.tightGap),
                                  Text(
                                    whyLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TenturaText.bodySmall(tt.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (footer != null) ...[
              SizedBox(height: tt.tightGap),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
