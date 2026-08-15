import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';

import 'package:tentura/features/coordination_item/ui/bloc/item_actions_cubit.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_state.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_overflow_menu.dart';

/// User-facing title when a semantic thread row has no item title yet.
String threadTitleFallback(L10n l10n, RequestThread thread) {
  if (thread.isGeneral) {
    return l10n.threadGeneralTitle;
  }
  final item = thread.item;
  if (item != null && item.title.trim().isNotEmpty) {
    return item.title.trim();
  }
  return switch (thread.kind) {
    RequestThreadKind.ask => l10n.coordinationAskCardLabel,
    RequestThreadKind.promise => l10n.coordinationPromiseCardLabel,
    RequestThreadKind.blocker => l10n.coordinationBlockerCardLabel,
    RequestThreadKind.general => l10n.threadGeneralTitle,
  };
}

String threadGeneralAppBarTitle(L10n l10n, Beacon beacon) =>
    beacon.title.isEmpty ? l10n.beaconViewTitle : beacon.title;

String _threadItemKindLabel(L10n l10n, CoordinationItem item) =>
    switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
    };

/// Thread body (messages) without a [Scaffold].
class ThreadDetail extends StatelessWidget {
  const ThreadDetail({
    required this.thread,
    this.onOpenCoordinationItem,
    this.onCoordinationSaved,
    this.beaconAuthorId = '',
    super.key,
  });

  final RequestThread thread;
  final ValueChanged<CoordinationItem>? onOpenCoordinationItem;
  final VoidCallback? onCoordinationSaved;
  final String beaconAuthorId;

  @override
  Widget build(BuildContext context) {
    return ThreadHost(
      child: TenturaChatColumn(
        child: Column(
          key: ValueKey(thread.threadId),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: BeaconRoomBody(
                beaconAuthorId: beaconAuthorId,
                onCoordinationSaved: onCoordinationSaved,
                onOpenCoordinationItem: onOpenCoordinationItem,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact header for a nested thread inside the ops|room split column.
class ThreadDetailColumnChrome extends StatelessWidget {
  const ThreadDetailColumnChrome({
    required this.onBack,
    required this.titleFallback,
    super.key,
  });

  final VoidCallback onBack;
  final String titleFallback;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.tightGap,
            vertical: tt.tightGap,
          ),
          child: Row(
            children: [
              Semantics(
                label: l10n.beaconRoomBackToChat,
                button: true,
                child: ExcludeSemantics(
                  child: IconButton(
                    tooltip: l10n.beaconRoomBackToChat,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
              Expanded(
                child: BlocBuilder<ItemActionsCubit, ItemActionsState>(
                  buildWhen: (p, c) => p.item != c.item,
                  builder: (context, state) => ThreadDetailTitle(
                    fallback: titleFallback,
                    item: state.item,
                  ),
                ),
              ),
              const ThreadDetailOverflowAction(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact two-line app-bar title shared by General and semantic threads.
class ThreadDetailAppBarTitle extends StatelessWidget {
  const ThreadDetailAppBarTitle({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final Widget subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.titleSmall(scheme.onSurface),
              ),
              subtitle,
            ],
          ),
        ),
      ],
    );
  }
}

/// Two-row app-bar title for General: request title plus involved-people pile.
class ThreadDetailGeneralTitle extends StatelessWidget {
  const ThreadDetailGeneralTitle({
    required this.title,
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    super.key,
  });

  final String title;
  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ThreadDetailAppBarTitle(
      title: title,
      subtitle: ExcludeSemantics(
        child: BeaconInvolvedPeopleFacePile(
          beacon: beacon,
          involvedProfiles: involvedProfiles,
          currentUserId: currentUserId,
        ),
      ),
    );
  }
}

/// Two-row app-bar title for a non-general thread: item title plus icon/meta.
class ThreadDetailTitle extends StatelessWidget {
  const ThreadDetailTitle({
    required this.fallback,
    required this.item,
    super.key,
  });

  final String fallback;
  final CoordinationItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final title = item.title.trim().isEmpty ? fallback : item.title.trim();
    final tt = context.tt;
    final statusColor = coordinationItemColor(tt, item.kind, item.status);
    final kindLabel = _threadItemKindLabel(l10n, item);
    final statusLabel = coordinationItemStatusLabel(l10n, item.status);
    final headerIcon = coordinationCompoundStatusIcon(
      kind: item.kind,
      status: item.status,
      isPlanStep: item.isPlanStep,
      tt: tt,
      size: tt.iconSize,
    );

    return Semantics(
      header: true,
      label: '$title. $kindLabel. $statusLabel',
      child: ExcludeSemantics(
        child: ThreadDetailAppBarTitle(
          title: title,
          subtitle: _ThreadDetailTitleMetaRow(
            item: item,
            headerIcon: headerIcon,
            kindLabel: kindLabel,
            statusLabel: statusLabel,
            statusColor: statusColor,
          ),
        ),
      ),
    );
  }
}

class _ThreadDetailTitleMetaRow extends StatelessWidget {
  const _ThreadDetailTitleMetaRow({
    required this.item,
    required this.headerIcon,
    required this.kindLabel,
    required this.statusLabel,
    required this.statusColor,
  });

  final CoordinationItem item;
  final Widget headerIcon;
  final String kindLabel;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final metaStyle = theme.textTheme.labelSmall?.copyWith(color: statusColor);
    final roomCubit = context.read<ThreadHostCubit>().roomCubit;

    Widget row(List<BeaconParticipant> participants) {
      final avatarTrail = item.kind.hasDirectedParties
          ? coordinationDirectedAvatarTrailForItem(
              creatorId: item.creatorId,
              targetPersonId: item.targetPersonId,
              participants: participants,
              avatarSize: tt.avatarTinySize,
            )
          : null;
      return Row(
        children: [
          if (avatarTrail != null) ...[
            avatarTrail,
            SizedBox(width: tt.rowGap),
          ],
          headerIcon,
          SizedBox(width: tt.iconTextGap),
          Flexible(
            child: Text(
              kindLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ),
          SizedBox(width: tt.rowGap),
          Flexible(
            child: Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ),
        ],
      );
    }

    if (roomCubit == null) {
      return row(const []);
    }
    return BlocBuilder<RoomCubit, RoomState>(
      bloc: roomCubit,
      buildWhen: (p, c) => p.participants != c.participants,
      builder: (context, roomState) => row(roomState.participants),
    );
  }
}

class ThreadDetailOverflowAction extends StatelessWidget {
  const ThreadDetailOverflowAction({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemActionsCubit, ItemActionsState>(
      buildWhen: (p, c) => p.item != c.item || p.isLoading != c.isLoading,
      builder: (context, state) => CoordinationItemDiscussionOverflowMenu(
        item: state.item,
        isLoading: state.isLoading,
      ),
    );
  }
}
