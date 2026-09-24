import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';
import '../widget/updates_feed_pane.dart';

@RoutePage()
/// Full notification history (all surfaces, unscoped).
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocProvider(
      create: (_) => UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.history,
      ),
      child: Scaffold(
        backgroundColor: tt.bg,
        appBar: TenturaTopBar.of(
          context,
          leading: const AutoLeadingButton(),
          title: Text(l10n.notificationHistoryTitle),
        ),
        body: SafeArea(
          minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: const TenturaContentColumn(
            child: UpdatesFeedPane(showTitleRow: false),
          ),
        ),
      ),
    );
  }
}
