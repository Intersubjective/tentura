import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';

/// Formats the Receipts primary-tab label with optional unread suffix.
String formatInboxReceiptsTabLabel(String label, int unread) =>
    unread > 0 ? '$label ($unread)' : label;

/// Receipts primary-tab label with the authoritative unread-receipt count.
class InboxReceiptsTabLabel extends StatelessWidget {
  const InboxReceiptsTabLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => StreamBuilder<AttentionSummary>(
    stream: GetIt.I<AttentionCase>().unreadSummary,
    initialData: GetIt.I<AttentionCase>().snapshot.summary,
    builder: (context, snapshot) {
      final unread = snapshot.data?.unreadTotal ?? 0;
      final text = formatInboxReceiptsTabLabel(label, unread);
      return Semantics(
        identifier: 'updates-unread-count-$unread',
        child: Text(text),
      );
    },
  );
}
