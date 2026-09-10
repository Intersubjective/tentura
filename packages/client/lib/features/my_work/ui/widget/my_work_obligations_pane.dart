import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/test_ids.dart';

/// Live obligations feed for My Work, backed by [AttentionView.needsYou].
class MyWorkObligationsPane extends StatelessWidget {
  const MyWorkObligationsPane({super.key});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key(TestIds.myWorkObligationsPane),
      child: BlocProvider(
        create: (_) => UpdatesFeedCubit(
          destinationId: AttentionFeedDestinationId.myWorkObligations,
          pinnedView: AttentionView.needsYou,
        ),
        child: const UpdatesFeedPane(
          offeredViews: [AttentionView.needsYou],
          showViewControl: false,
        ),
      ),
    );
  }
}
