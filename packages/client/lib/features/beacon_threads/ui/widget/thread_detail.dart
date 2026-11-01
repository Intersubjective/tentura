import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/browser_context_menu_hold.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';
import 'package:tentura/ui/widget/tentura_focus_semantics.dart';

String _threadItemKindLabel(L10n l10n, CoordinationItem item) =>
    switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.plan =>
        item.isPlanStep
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
    this.beaconAuthor,
    this.capabilities = const RoomCapabilities.request(),
    this.postRoot,
    this.postArchived = false,
    this.closureHadNoFinalCheck,
    super.key,
  });

  final RequestThread thread;
  final ValueChanged<CoordinationItem>? onOpenCoordinationItem;
  final VoidCallback? onCoordinationSaved;
  final String beaconAuthorId;
  final Profile? beaconAuthor;
  final RoomCapabilities capabilities;
  final RoomPostRootPin? postRoot;

  /// Post rooms only: the Post is closed or past its `expiresAt`.
  final bool postArchived;

  /// Passed through to [BeaconRoomBody] (#825).
  final bool? closureHadNoFinalCheck;

  @override
  Widget build(BuildContext context) {
    // Right-click on a message opens its actions, so on web the browser's
    // own menu stays off for as long as the room is up (#456, #623).
    return BrowserContextMenuHold(
      child: ThreadHost(
        child: TenturaChatColumn(
          child: Column(
            key: ValueKey(thread.threadId),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BeaconRoomBody(
                  beaconAuthorId: beaconAuthorId,
                  beaconAuthor: beaconAuthor,
                  onCoordinationSaved: onCoordinationSaved,
                  onOpenCoordinationItem: onOpenCoordinationItem,
                  capabilities: capabilities,
                  postRoot: postRoot,
                  postArchived: postArchived,
                  closureHadNoFinalCheck: closureHadNoFinalCheck,
                ),
              ),
            ],
          ),
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
    required this.thread,
    super.key,
  });

  final VoidCallback onBack;
  final String titleFallback;
  final RequestThread thread;

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
              // #415: the label wrapper carries the button's focus state.
              TenturaFocusSemantics(
                builder: (_, focused) => Semantics(
                  label: l10n.beaconRoomBackToChat,
                  button: true,
                  focused: focused,
                  child: ExcludeSemantics(
                    child: IconButton(
                      tooltip: l10n.beaconRoomBackToChat,
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ThreadDetailTitle(
                  fallback: titleFallback,
                  item: thread.item,
                  kind: thread.kind,
                ),
              ),
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
    this.trailing,
    this.padding = EdgeInsetsDirectional.zero,
    super.key,
  });

  final String title;
  final Widget subtitle;

  /// Pane-level actions (e.g. the split header ⋮) kept inside the title so
  /// the discussion header spans exactly the discussion pane.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
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
          ?trailing,
        ],
      ),
    );
  }
}

/// Two-row app-bar title for a non-general thread: item title plus icon/meta.
class ThreadDetailTitle extends StatelessWidget {
  const ThreadDetailTitle({
    required this.fallback,
    required this.item,
    required this.kind,
    super.key,
  });

  final String fallback;
  final CoordinationItem? item;
  final RequestThreadKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (item == null) {
      final title = switch (kind) {
        RequestThreadKind.ask => l10n.coordinationAskCardLabel,
        RequestThreadKind.promise => l10n.coordinationPromiseCardLabel,
        RequestThreadKind.blocker => l10n.coordinationBlockerCardLabel,
        RequestThreadKind.general => fallback,
      };
      return ThreadDetailAppBarTitle(
        title: title,
        subtitle: const SizedBox.shrink(),
      );
    }
    final resolvedItem = item!;
    final title = resolvedItem.title.trim().isEmpty
        ? fallback
        : resolvedItem.title.trim();
    final tt = context.tt;
    final statusColor = coordinationItemColor(
      tt,
      resolvedItem.kind,
      resolvedItem.status,
    );
    final kindLabel = _threadItemKindLabel(l10n, resolvedItem);
    final statusLabel = coordinationItemStatusLabel(l10n, resolvedItem.status);
    final headerIcon = coordinationCompoundStatusIcon(
      kind: resolvedItem.kind,
      status: resolvedItem.status,
      isPlanStep: resolvedItem.isPlanStep,
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
            item: resolvedItem,
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
