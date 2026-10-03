import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';

import '../bloc/updates_feed_cubit.dart';
import '../widget/updates_feed_pane.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/consts.dart';

@RoutePage()
/// Full notification history (all surfaces, unscoped).
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final _searchOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _searchOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final compact = context.windowClass == WindowClass.compact;

    return BlocProvider(
      create: (_) => UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.history,
      ),
      child: HomeRailFrame(
        selectedTab: HomeTab.inbox,
        child: Builder(
          builder: (context) {
            final hasUnread = context.select<UpdatesFeedCubit, bool>(
              (cubit) => cubit.state.summary.unreadTotal > 0,
            );
            return Scaffold(
              backgroundColor: tt.bg,
              // "Read all" and search live in the bar, not on a row of
              // their own under it (UI review #201).
              appBar: TenturaTopBar.of(
                context,
                leading: const AutoLeadingWithFallback(
                  fallbackPath: kPathInbox,
                ),
                title: Text(l10n.notificationHistoryTitle),
                actions: [
                  TenturaTextAction(
                    label: l10n.updatesMarkAllSeen,
                    onPressed: hasUnread
                        ? () => context.read<UpdatesFeedCubit>().markAllSeen()
                        : null,
                  ),
                  if (compact)
                    ValueListenableBuilder<bool>(
                      valueListenable: _searchOpen,
                      builder: (context, open, _) => IconButton(
                        tooltip: l10n.updatesSearchHint,
                        isSelected: open,
                        onPressed: () => _searchOpen.value = !open,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                ],
              ),
              body: SafeArea(
                minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                child: TenturaContentColumn(
                  child: UpdatesFeedPane(searchOpen: _searchOpen),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
