import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import '../bloc/activity_offers_cubit.dart';
import '../bloc/inbox_cubit.dart';
import '../widget/activity_stream_view.dart';

@RoutePage()
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    @QueryParam(kQueryHomeTab) this.initialTab,
    super.key,
  });

  final String? initialTab;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  var _lastHandledReceiptsOpenCount = 0;
  final ScrollController _activityScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == kInboxTabReceipts) {
      _lastHandledReceiptsOpenCount = -1;
    }
  }

  @override
  void dispose() {
    _activityScrollController.dispose();
    super.dispose();
  }

  void _consumeReceiptsIntentIfNeeded(BuildContext context) {
    final reselect = context.read<HomeTabReselectCubit>().state;
    final fromRoute = widget.initialTab == kInboxTabReceipts;
    final fromReselect =
        reselect.inboxReceiptsOpenCount > _lastHandledReceiptsOpenCount;
    if (!fromRoute && !fromReselect) return;
    _lastHandledReceiptsOpenCount = reselect.inboxReceiptsOpenCount;
  }

  void _scrollActivityFeedToTop() {
    if (!_activityScrollController.hasClients) return;
    unawaited(
      _activityScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _InboxReceiptsIntentBinder(
      onFirstFrame: _consumeReceiptsIntentIfNeeded,
      child: _InboxMovedSnackBarDismisser(
        child: BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
          listenWhen: (prev, curr) =>
              prev.inboxReselectCount != curr.inboxReselectCount,
          listener: (context, _) => _scrollActivityFeedToTop(),
          child: BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
            listenWhen: (prev, curr) =>
                prev.inboxReceiptsOpenCount != curr.inboxReceiptsOpenCount,
            listener: (context, state) {
              _lastHandledReceiptsOpenCount = state.inboxReceiptsOpenCount;
            },
            child: BlocListener<InboxCubit, InboxState>(
              listenWhen: (prev, curr) =>
                  curr.pendingMovedNudge != null &&
                  prev.pendingMovedNudge != curr.pendingMovedNudge,
              listener: (context, state) {
                final msg = state.pendingMovedNudge;
                if (msg == null) return;
                final l10n = L10n.of(context)!;
                showSnackBar(
                  context,
                  text: msg.toL10n(l10n.localeName),
                  action: msg.navigatesToRejectedArchive
                      ? SnackBarAction(
                          label: l10n.inboxViewInTab,
                          onPressed: () {
                            unawaited(openInboxRejectedArchive(context));
                          },
                        )
                      : null,
                );
                context.read<InboxCubit>().clearPendingMovedNudge();
              },
              child: Builder(
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  final l10n = L10n.of(context)!;
                  final useExpandedPane =
                      context.windowClass == WindowClass.expanded;
                  final tt = context.tt;

                  return Scaffold(
                    backgroundColor: scheme.surface,
                    appBar: TenturaTopBar.of(
                      context,
                      tone: TenturaTopBarTone.primary,
                      alignment: useExpandedPane
                          ? TenturaTopBarAlignment.fullWidth
                          : TenturaTopBarAlignment.content,
                      title: Text(
                        l10n.inbox,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.titleLarge(scheme.onPrimary),
                      ),
                      actions: const [
                        _ActivityMarkAllSeenButton(),
                        _InboxOverflowMenu(showNotificationHistory: true),
                      ],
                    ),
                    body: SafeArea(
                      minimum: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ),
                      child: TenturaContentColumn(
                        child: _InboxFeedKeepAlive(
                          child: _inboxActivityFeedBody(
                            context,
                            scrollController: _activityScrollController,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxReceiptsIntentBinder extends StatefulWidget {
  const _InboxReceiptsIntentBinder({
    required this.onFirstFrame,
    required this.child,
  });

  final void Function(BuildContext context) onFirstFrame;
  final Widget child;

  @override
  State<_InboxReceiptsIntentBinder> createState() =>
      _InboxReceiptsIntentBinderState();
}

class _InboxReceiptsIntentBinderState extends State<_InboxReceiptsIntentBinder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFirstFrame(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hides the "beacon moved" snack bar when the user leaves the Inbox home tab.
class _InboxMovedSnackBarDismisser extends StatelessWidget {
  const _InboxMovedSnackBarDismisser({required this.child});

  final Widget child;

  void _clearSnackBars(BuildContext context) {
    (ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState)
        ?.clearSnackBars();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<HomeAttentionCubit, HomeAttentionState>(
      listenWhen: (prev, curr) =>
          prev.activeHomeTab == HomeTab.inbox &&
          curr.activeHomeTab != HomeTab.inbox,
      listener: (context, _) => _clearSnackBars(context),
      child: child,
    );
  }
}

class _InboxFeedKeepAlive extends StatefulWidget {
  const _InboxFeedKeepAlive({required this.child});

  final Widget child;

  @override
  State<_InboxFeedKeepAlive> createState() => _InboxFeedKeepAliveState();
}

class _InboxFeedKeepAliveState extends State<_InboxFeedKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(
      key: const PageStorageKey<String>('inbox-activity-feed'),
      child: widget.child,
    );
  }
}

Widget _inboxActivityFeedBody(
  BuildContext context, {
  required ScrollController scrollController,
}) {
  final userId = context.read<ProfileCubit>().state.profile.id;
  return MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) {
          final cubit = ActivityOffersCubit(userId: userId);
          unawaited(cubit.loadFirst());
          return cubit;
        },
      ),
      BlocProvider(
        create: (_) => UpdatesFeedCubit(
          destinationId: AttentionFeedDestinationId.activityStream,
        ),
      ),
    ],
    child: ActivityStreamView(scrollController: scrollController),
  );
}

class _ActivityMarkAllSeenButton extends StatelessWidget {
  const _ActivityMarkAllSeenButton();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final attention = GetIt.I<AttentionCase>();

    return StreamBuilder<AttentionSurfaceSummary>(
      stream: attention.surfaceSummary,
      initialData: const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      ),
      builder: (context, snapshot) {
        final unread = snapshot.data?.activityUnreadTotal ?? 0;
        return IconButton(
          icon: const Icon(Icons.done_all),
          tooltip: l10n.updatesMarkAllSeen,
          onPressed: unread > 0
              ? () => unawaited(
                    attention.markAllSeen(surface: AttentionSurface.activity),
                  )
              : null,
        );
      },
    );
  }
}

class _InboxOverflowMenu extends StatelessWidget {
  const _InboxOverflowMenu({this.showNotificationHistory = false});

  final bool showNotificationHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocSelector<InboxCubit, InboxState, int>(
      selector: (state) => state.watching.length,
      builder: (context, watchingCount) {
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: context.tt.buttonHeight,
            minHeight: context.tt.buttonHeight,
          ),
          onSelected: (value) {
            if (value == 'watching') {
              unawaited(openInboxWatchingArchive(context));
            } else if (value == 'rejected') {
              unawaited(openInboxRejectedArchive(context));
            } else if (value == 'history') {
              unawaited(openNotificationHistory(context));
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'watching',
              child: Text('${l10n.inboxWatching} ($watchingCount)'),
            ),
            PopupMenuItem<String>(
              value: 'rejected',
              child: Text(l10n.inboxRejectedTitle),
            ),
            if (showNotificationHistory)
              PopupMenuItem<String>(
                value: 'history',
                child: Text(l10n.notificationHistoryTitle),
              ),
          ],
        );
      },
    );
  }
}

/// Pushes full-screen rejected archive, then refreshes the tab inbox when popped.
Future<void> openInboxRejectedArchive(BuildContext context) async {
  final cubit = context.read<InboxCubit>();
  await context.router.push(const InboxRejectedRoute());
  if (!context.mounted) return;
  await cubit.fetch();
}

/// Pushes full-screen watching archive, then refreshes the tab inbox when popped.
Future<void> openInboxWatchingArchive(BuildContext context) async {
  final cubit = context.read<InboxCubit>();
  await context.router.push(InboxWatchingRoute());
  if (!context.mounted) return;
  await cubit.fetch();
}

/// Pushes the all-surfaces notification history screen.
Future<void> openNotificationHistory(BuildContext context) async {
  await context.router.push(const UpdatesRoute());
}
