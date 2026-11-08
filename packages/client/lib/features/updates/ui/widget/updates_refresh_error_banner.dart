import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Full-width "couldn't refresh" banner over the updates feed.
class UpdatesRefreshErrorBanner extends StatelessWidget {
  const UpdatesRefreshErrorBanner({
    required this.onRetry,
    super.key,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: UpdatesRefreshErrorRow(
        onRetry: onRetry,
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.tightGap,
        ),
      ),
    );
  }
}

/// The "couldn't refresh" line with a Retry action, unboxed: used inline in
/// the inbox activity stream and inside [UpdatesRefreshErrorBanner].
class UpdatesRefreshErrorRow extends StatelessWidget {
  const UpdatesRefreshErrorRow({
    required this.onRetry,
    this.padding,
    super.key,
  });

  final VoidCallback onRetry;

  /// Defaults to the list-row horizontal inset with a tight vertical gap.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: tt.listRowPadding.left,
            vertical: tt.tightGap,
          ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: tt.warn),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Text(
              l10n.updatesRefreshFailedBanner,
              style: TenturaText.bodySmall(tt.text),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(l10n.myWorkRetry),
          ),
        ],
      ),
    );
  }
}
