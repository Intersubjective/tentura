import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';

/// Updates tab icon with the authoritative unread-receipt count.
class UpdatesNavbarItem extends StatelessWidget {
  const UpdatesNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) => StreamBuilder<AttentionSummary>(
    stream: GetIt.I<AttentionCase>().unreadSummary,
    initialData: GetIt.I<AttentionCase>().snapshot.summary,
    builder: (context, snapshot) {
      final unread = snapshot.data?.unreadTotal ?? 0;
      return Semantics(
        identifier: 'updates-unread-count-$unread',
        child: Badge.count(
          count: unread,
          isLabelVisible: unread > 0,
          child: Icon(
            selected ? Icons.notifications : Icons.notifications_outlined,
          ),
        ),
      );
    },
  );
}
