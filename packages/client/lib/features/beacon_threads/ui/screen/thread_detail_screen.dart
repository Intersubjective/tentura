import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_cubit.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

@RoutePage()
class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({
    @PathParam.inherit('id') required this.beaconId,
    @PathParam('threadId') required this.threadId,
    @QueryParam(kQueryMessageId) this.messageId,
    super.key,
  });

  final String beaconId;
  final String threadId;
  final String? messageId;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  bool _allowPop = false;
  bool _exitInProgress = false;
  RequestThread? _selectedThread;
  var _selectionStarted = false;
  WindowClass? _lastWindowClass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureSelection());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wc = context.windowClass;
    final previous = _lastWindowClass;
    _lastWindowClass = wc;
    if (previous == null) return;
    if (previous != WindowClass.expanded && wc == WindowClass.expanded) {
      context.read<ThreadHostCubit>().scheduleWindowClassTransition(() {
        if (!mounted) return;
        setState(() => _allowPop = true);
        context.router.pop();
      });
    }
  }

  Future<void> _ensureSelection() async {
    if (_selectionStarted || !mounted) return;
    _selectionStarted = true;

    final threadsCubit = context.read<ThreadsCubit>();
    var threadsState = threadsCubit.state;
    if (!threadsState.isSuccess) {
      threadsState = await threadsCubit.stream.firstWhere(
        (s) => s.isSuccess,
      );
    }
    if (!mounted) return;

    final row = _resolveAccessibleRow(threadsState);
    if (row == null) {
      setState(() => _selectedThread = null);
      return;
    }

    await context.read<ThreadHostCubit>().select(row);
    if (!mounted) return;

    final roomCubit = context.read<ThreadHostCubit>().roomCubit;
    roomCubit?.prepareThreadScroll(
      messageId: widget.messageId,
      coordinationItemId: row.item?.id,
    );

    setState(() => _selectedThread = row);
  }

  RequestThread? _resolveAccessibleRow(ThreadsState state) {
    if (state.threads.isEmpty) return null;
    for (final thread in state.threads) {
      if (thread.threadId == widget.threadId) {
        return thread;
      }
    }
    return state.firstAccessible;
  }

  Future<void> _closeThenPop() async {
    if (_exitInProgress) return;
    _exitInProgress = true;
    await context.read<ThreadHostCubit>().clear();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.router.pop();
    });
  }

  void _onOpenCoordinationItem(CoordinationItem item) {
    if (planItemSuppressesItemDiscussion(item)) {
      context.read<ThreadHostCubit>().roomCubit?.prepareThreadScroll(
        messageId: item.threadAnchorMessageId,
        coordinationItemId: item.id,
      );
      return;
    }
    unawaited(
      context.router.replace(
        ThreadDetailRoute(
          threadId: item.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final windowClass = context.windowClass;
    final showClosedBanner =
        windowClass == WindowClass.compact ||
        windowClass == WindowClass.regular;

    return BlocBuilder<ThreadsCubit, ThreadsState>(
      buildWhen: (p, c) =>
          p.status != c.status ||
          p.threads != c.threads ||
          p.loadError != c.loadError,
      builder: (context, threadsState) {
        if (!threadsState.isSuccess) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        if (threadsState.threads.isEmpty) {
          return _AdmissionPlaceholder(beaconId: widget.beaconId);
        }

        return BlocBuilder<ThreadHostCubit, ThreadHostState>(
          buildWhen: (p, c) =>
              p.switching != c.switching || p.openThreadId != c.openThreadId,
          builder: (context, hostState) {
            if (hostState.switching || _selectedThread == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator.adaptive()),
              );
            }

            final thread = _selectedThread!;
            final item = thread.item;
            final beaconState = context.watch<BeaconViewCubit>().state;
            final beacon = beaconState.beacon;
            final titleFallback = thread.isGeneral
                ? threadGeneralAppBarTitle(l10n, beacon)
                : threadTitleFallback(l10n, thread);

            final detail = ThreadDetail(
              thread: thread,
              beaconAuthorId: beacon.author.id,
              onCoordinationSaved: () =>
                  unawaited(context.read<ThreadsCubit>().fetch()),
              onOpenCoordinationItem: _onOpenCoordinationItem,
            );

            final body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showClosedBanner && beacon.id.isNotEmpty)
                  ClosedRequestBanner(beacon: beacon),
                Expanded(child: detail),
              ],
            );

            // AppBar title/overflow also read ItemActionsCubit — provider must
            // wrap Scaffold, not only the body ThreadDetail.
            Widget scaffold = Scaffold(
              appBar: TenturaTopBar.of(
                context,
                leading: BackButton(
                  onPressed: () => unawaited(_closeThenPop()),
                ),
                title: thread.isGeneral
                    ? ThreadDetailGeneralTitle(
                        title: titleFallback,
                        beacon: beacon,
                        involvedProfiles: beaconState.activeHelpOfferUsers,
                        currentUserId: beaconState.myProfile.id,
                      )
                    : item == null
                    ? Text(
                        titleFallback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : BlocBuilder<ItemActionsCubit, ItemActionsState>(
                        buildWhen: (p, c) => p.item != c.item,
                        builder: (context, state) => ThreadDetailTitle(
                          fallback: titleFallback,
                          item: state.item,
                        ),
                      ),
                actions: item == null
                    ? null
                    : const [ThreadDetailOverflowAction()],
              ),
              body: body,
            );
            if (item != null) {
              scaffold = BlocProvider(
                create: (_) => ItemActionsCubit(item: item),
                child: scaffold,
              );
            }

            return PopScope(
              canPop: _allowPop,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                unawaited(_closeThenPop());
              },
              child: scaffold,
            );
          },
        );
      },
    );
  }
}

class _AdmissionPlaceholder extends StatelessWidget {
  const _AdmissionPlaceholder({required this.beaconId});

  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      builder: (context, state) {
        final message = state.isRoomAdmissionBlocked
            ? (state.coordinationDeniesRoomAdmission
                  ? l10n.beaconRoomNoAdmission
                  : l10n.beaconRoomWaitingForApproval)
            : l10n.beaconItemsEmptyPlaceholder;
        return Scaffold(
          appBar: TenturaTopBar.of(
            context,
            title: Text(l10n.beaconViewTitle),
            leading: BackButton(
              onPressed: () => context.router.pop(),
            ),
          ),
          body: Center(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
