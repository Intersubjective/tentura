import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/request_access_reason.dart';

/// Explains observer access through a related Request.
class RequestAccessReasonBanner extends StatelessWidget {
  const RequestAccessReasonBanner({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  static const openParentKey = Key('request-access-reason-open-parent');

  @visibleForTesting
  static const bodyTextKey = Key('request-access-reason-body');

  @override
  Widget build(BuildContext context) {
    if (!requestAccessViaRelated(beacon)) return const SizedBox.shrink();

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: tt.cardGap),
      child: TenturaTechCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: tt.iconSize,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Text(
                l10n.requestAccessViaRelatedRequest,
                key: bodyTextKey,
                maxLines: 5,
                style: TenturaText.bodySmall(scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
