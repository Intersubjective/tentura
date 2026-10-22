import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// CHAT surface: General conversation inline (no scaffold chrome).
class BeaconRoomSurface extends StatefulWidget {
  const BeaconRoomSurface({
    required this.host,
    required this.roomLease,
    this.legacyThreadId,
    this.messageId,
    this.coordinationItemId,
    this.onCoordinationSaved,
    this.onOpenCoordinationItem,
    this.postRoot,
    this.pinnedStrip,
    super.key,
  });

  final RoomHost host;
  final BeaconRoomLease roomLease;

  /// When set to a non-[RequestThread.generalId] value, shows legacy-unavailable.
  final String? legacyThreadId;

  final String? messageId;
  final String? coordinationItemId;
  final VoidCallback? onCoordinationSaved;
  final void Function(CoordinationItem item)? onOpenCoordinationItem;

  /// Post rooms only: the pinned root strip.
  final RoomPostRootPin? postRoot;

  /// Overrides the host's pinned strip; null keeps the host's.
  final RoomPinnedStrip? pinnedStrip;

  @override
  State<BeaconRoomSurface> createState() => _BeaconRoomSurfaceState();
}

class _BeaconRoomSurfaceState extends State<BeaconRoomSurface> {
  RequestThread? _generalThread;
  var _roomReady = false;
  late Stream<void> _hostChanges = widget.host.changes;
  late bool _wasAdmissionBlocked;
  StreamSubscription<void>? _hostSub;
  StreamSubscription<ThreadsState>? _threadsSub;
  var _ensuring = false;

  static const _fallbackGeneral = RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
  );

  /// #484: the thread list failed to load for a Request room. Request rooms
  /// are General-only, so the surface opens a stand-in General instead of
  /// leaving the room without its composer. Post rooms (no Request
  /// collaborators) keep the plain placeholder.
  /// A viewer still waiting for (or denied) admission gets no stand-in room:
  /// no RoomCubit, no room reads; the admission UI in [build] shows instead.
  bool _usesFallbackGeneral(ThreadsState threadsState) =>
      !widget.host.isAdmissionBlocked &&
      threadsState.threads.isEmpty &&
      threadsState.hasError &&
      widget.host.capabilities.coordinationItems;

  bool _isLegacyThreadId() {
    final id = widget.legacyThreadId?.trim();
    return id != null && id.isNotEmpty && id != RequestThread.generalId;
  }

  @override
  void initState() {
    super.initState();
    // Read now, not lazily on the first change: by then the host has already
    // flipped and the blocked -> admitted transition would be missed.
    _wasAdmissionBlocked = widget.host.isAdmissionBlocked;
    _hostSub = widget.host.changes.listen((_) => _onHostChanged());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _threadsSub = context.read<ThreadsCubit>().stream.listen(
        (_) => unawaited(_ensureRoom()),
      );
      unawaited(_ensureRoom());
    });
  }

  @override
  void didUpdateWidget(covariant BeaconRoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _hostChanges = widget.host.changes;
      unawaited(_hostSub?.cancel());
      _wasAdmissionBlocked = widget.host.isAdmissionBlocked;
      _hostSub = widget.host.changes.listen((_) => _onHostChanged());
    }
  }

  @override
  void dispose() {
    unawaited(_hostSub?.cancel());
    unawaited(_threadsSub?.cancel());
    widget.roomLease.release(this);
    super.dispose();
  }

  /// #609: a viewer admitted after the room was first set up (e.g. while the
  /// thread list was failed) gets the room now, and the thread list is
  /// retried in the background when it holds no General for them yet.
  void _onHostChanged() {
    final blocked = widget.host.isAdmissionBlocked;
    final admitted = _wasAdmissionBlocked && !blocked;
    _wasAdmissionBlocked = blocked;
    if (!admitted || !mounted) return;
    final threadsCubit = context.read<ThreadsCubit>();
    if (threadsCubit.state.general == null) {
      unawaited(threadsCubit.fetch(silent: true));
    }
    unawaited(_ensureRoom());
  }

  /// Sets the room up once; re-run on admission and on thread list changes
  /// until it is (#609), so a later General or admission is not missed.
  Future<void> _ensureRoom() async {
    if (_ensuring || _generalThread != null) return;
    _ensuring = true;
    try {
      await _setUpRoom();
    } finally {
      _ensuring = false;
    }
  }

  Future<void> _setUpRoom() async {
    if (!mounted || _isLegacyThreadId()) return;

    final threadsCubit = context.read<ThreadsCubit>();
    var threadsState = threadsCubit.state;
    if (!threadsState.isSuccess) {
      threadsState = await threadsCubit.stream.firstWhere((s) => s.isSuccess);
    }
    if (!mounted) return;

    // #484: a failed thread list (e.g. a busy database right after "Make live
    // without sending") must not leave a Request room without its composer;
    // the admission gate in [build] still decides whether the viewer sees it.
    // A successful empty list is a real "no room for you" answer and stays a
    // placeholder.
    final general =
        threadsState.general ??
        (_usesFallbackGeneral(threadsState) ? _fallbackGeneral : null);
    if (general == null) return;

    await widget.roomLease.acquire(this, general);
    if (!mounted) return;

    final roomCubit = context.read<ThreadHostCubit>().roomCubit;
    roomCubit?.prepareThreadScroll(
      messageId: widget.messageId,
      coordinationItemId: widget.coordinationItemId ?? general.item?.id,
    );

    setState(() {
      _generalThread = general;
      _roomReady = widget.roomLease.isReady;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    if (_isLegacyThreadId()) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Text(
            l10n.beaconLegacyThreadUnavailable,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return BlocBuilder<ThreadsCubit, ThreadsState>(
      buildWhen: (p, c) =>
          p.status != c.status ||
          p.threads != c.threads ||
          p.loadError != c.loadError,
      builder: (context, threadsState) {
        if (threadsState.status is StateIsLoading &&
            threadsState.threads.isEmpty) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        if (!threadsState.isSuccess) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        return StreamBuilder<void>(
          stream: _hostChanges,
          builder: (context, _) {
            final host = widget.host;
            if (host.isAdmissionBlocked) {
              return Center(
                child: Text(
                  host.coordinationDeniesAdmission
                      ? l10n.beaconRoomNoAdmission
                      : l10n.beaconRoomWaitingForApproval,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            if (threadsState.threads.isEmpty &&
                !_usesFallbackGeneral(threadsState)) {
              return Center(
                child: Text(
                  l10n.beaconItemsEmptyPlaceholder,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            return BlocBuilder<ThreadHostCubit, ThreadHostState>(
              buildWhen: (p, c) =>
                  p.switching != c.switching ||
                  p.openThreadId != c.openThreadId,
              builder: (context, hostState) {
                if (hostState.switching ||
                    !_roomReady ||
                    _generalThread == null) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                return ThreadDetail(
                  thread: _generalThread!,
                  beaconAuthorId: host.author.id,
                  beaconAuthor: host.author,
                  capabilities: widget.pinnedStrip == null
                      ? host.capabilities
                      : host.capabilities.withPinnedStrip(widget.pinnedStrip!),
                  postRoot: widget.postRoot,
                  onCoordinationSaved: widget.onCoordinationSaved,
                  onOpenCoordinationItem: widget.onOpenCoordinationItem,
                );
              },
            );
          },
        );
      },
    );
  }
}
