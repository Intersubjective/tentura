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

  @override
  State<BeaconRoomSurface> createState() => _BeaconRoomSurfaceState();
}

class _BeaconRoomSurfaceState extends State<BeaconRoomSurface> {
  RequestThread? _generalThread;
  var _roomReady = false;
  late Stream<void> _hostChanges = widget.host.changes;

  bool _isLegacyThreadId() {
    final id = widget.legacyThreadId?.trim();
    return id != null && id.isNotEmpty && id != RequestThread.generalId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureRoom());
    });
  }

  @override
  void didUpdateWidget(covariant BeaconRoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) _hostChanges = widget.host.changes;
  }

  @override
  void dispose() {
    widget.roomLease.release(this);
    super.dispose();
  }

  Future<void> _ensureRoom() async {
    if (!mounted || _isLegacyThreadId()) return;

    final threadsCubit = context.read<ThreadsCubit>();
    var threadsState = threadsCubit.state;
    if (!threadsState.isSuccess) {
      threadsState = await threadsCubit.stream.firstWhere((s) => s.isSuccess);
    }
    if (!mounted) return;

    if (threadsState.threads.isEmpty) return;

    final general = threadsState.general;
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

            if (threadsState.threads.isEmpty) {
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
                  p.switching != c.switching || p.openThreadId != c.openThreadId,
              builder: (context, hostState) {
                if (hostState.switching || !_roomReady || _generalThread == null) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                return ThreadDetail(
                  thread: _generalThread!,
                  beaconAuthorId: host.author.id,
                  beaconAuthor: host.author,
                  capabilities: host.capabilities,
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
