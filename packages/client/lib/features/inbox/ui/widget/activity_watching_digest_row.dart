import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/components/tentura_attention_summary_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Aggregate watching-updates row (design §5.3).
class ActivityWatchingDigestRow extends StatelessWidget {
  const ActivityWatchingDigestRow({
    required this.count,
    super.key,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final label = l10n.activityWatchingDigest(count);
    return TenturaAttentionSummaryRow(
      label: label,
      semanticsLabel: label,
      inkWellKey: TestIds.key(TestIds.activityWatchingDigest),
      onTap: () => unawaited(context.router.push(InboxWatchingRoute())),
    );
  }
}
