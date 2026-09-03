import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Persistent, non-dismissible status card when a request is closed (status 6).
class ClosedRequestBanner extends StatelessWidget {
  const ClosedRequestBanner({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    if (beacon.status != BeaconStatus.closed) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: tt.cardGap),
      child: TenturaTechCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = windowClassForWidth(constraints.maxWidth) ==
                WindowClass.compact;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TenturaStatusText(
                  l10n.requestClosedBannerTitle,
                  tone: TenturaTone.neutral,
                  maxLines: 2,
                ),
                SizedBox(height: tt.tightGap),
                Text(
                  l10n.requestClosedBannerBody,
                  style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                ),
              ],
            );
            final cta = TenturaCommandButton(
              label: l10n.closedRequestViewMyReviewsAction,
              onPressed: () => context.router.push(
                ReceivedReviewsRoute(id: beacon.id),
              ),
            );
            final header = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: tt.iconSize,
                  color: scheme.onSurfaceVariant,
                ),
                SizedBox(width: tt.iconTextGap),
                Expanded(child: copy),
                if (!compact) ...[
                  SizedBox(width: tt.iconTextGap),
                  cta,
                ],
              ],
            );
            if (!compact) {
              return header;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                SizedBox(height: tt.rowGap),
                SizedBox(width: double.infinity, child: cta),
              ],
            );
          },
        ),
      ),
    );
  }
}
