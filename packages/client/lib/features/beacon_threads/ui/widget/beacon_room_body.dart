import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/app/router/root_router.dart';

import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';

import '../bloc/room_cubit.dart';
import '../coordination_room_navigation.dart';
import 'fact_actions_sheet.dart';
import 'fact_picker_sheet.dart';
import 'room_file_attachment_open.dart';
import 'room_readers_sheet.dart';

/// Body-only room UI (message list + composer); expects [RoomCubit] above.
class BeaconRoomBody extends StatefulWidget {
  const BeaconRoomBody({
    super.key,
    this.enableComposer = true,
    this.beaconAuthorId = '',
    this.beaconAuthor,
    this.onCoordinationSaved,
    this.onOpenCoordinationItem,
    this.capabilities = const RoomCapabilities.request(),
    this.postRoot,
  });

  final bool enableComposer;

  /// Request-only features the hosting screen offers in this room.
  final RoomCapabilities capabilities;

  /// Post rooms only: root message pinned above the messages.
  final RoomPostRootPin? postRoot;

  /// Beacon author id for coordination target lists (from beacon view shell).
  final String beaconAuthorId;

  /// Beacon author profile for reader display resolution (from beacon view shell).
  final Profile? beaconAuthor;

  /// Called after a coordination item is created from the room (e.g. refresh Items tab).
  final VoidCallback? onCoordinationSaved;

  /// Opens an item thread or scrolls to a plan anchor; host-owned when nested.
  final ValueChanged<CoordinationItem>? onOpenCoordinationItem;

  @override
  State<BeaconRoomBody> createState() => _BeaconRoomBodyState();
}

String _readWatermarksFingerprint(Map<String, RoomReadWatermark> watermarks) {
  return watermarks.entries
      .map(
        (e) => '${e.key}|${e.value.lastSeenAt.toIso8601String()}',
      )
      .join(',');
}

class _BeaconRoomBodyState extends State<BeaconRoomBody> {
  final _basicChatKey = GlobalKey<BasicChatBodyState>();

  bool _suppressesRichMessageActions(RoomMessage message) =>
      message.semanticMarker == BeaconRoomSemanticMarker.blocker ||
      message.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
      message.semanticMarker == BeaconRoomSemanticMarker.done;

  /// Non-empty text for [BeaconFactCard]; attachments use names or [L10n.beaconRoomPinFactAttachmentBodyFallback].
  String _pinFactTextForMessage(RoomMessage message, L10n l10n) {
    return pinFactTextForPin(
      body: message.body,
      attachmentCount: message.attachments.length,
      attachmentFileNames: [
        for (final a in message.attachments)
          if (a.fileName.trim().isNotEmpty) a.fileName.trim(),
      ],
      attachmentFallback: l10n.beaconRoomPinFactAttachmentBodyFallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final myProfile = GetIt.I<ProfileCubit>().state.profile;

    return MultiBlocListener(
      listeners: [
        BlocListener<RoomCubit, RoomState>(
          listenWhen: (p, c) =>
              c.scrollToMessageId != null &&
              c.scrollToMessageId != p.scrollToMessageId,
          listener: (ctx, state) {
            final id = state.scrollToMessageId;
            if (id == null) return;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!ctx.mounted) return;
              await (_basicChatKey.currentState?.scrollToMessage(id) ??
                  Future.value(false));
              if (ctx.mounted) {
                ctx.read<RoomCubit>().clearScrollToMessageTarget();
              }
            });
          },
        ),
        BlocListener<RoomCubit, RoomState>(
          listenWhen: (p, c) =>
              c.pendingFactsFocusFactId != null &&
              c.pendingFactsFocusFactId != p.pendingFactsFocusFactId,
          listener: (ctx, state) async {
            final fid = state.pendingFactsFocusFactId;
            if (fid == null) return;
            ctx.read<RoomCubit>().clearPendingFactsFocus();
            if (!ctx.mounted) return;
            final cub = ctx.read<RoomCubit>();
            BeaconFactCard? focused;
            for (final f in state.factCards) {
              if (f.id == fid) {
                focused = f;
                break;
              }
            }
            if (focused != null && ctx.mounted) {
              await showFactActionsSheet(
                ctx,
                cubit: cub,
                fact: focused,
                onQuoteInChat: (f) => _quoteFactInChat(cub, f),
              );
            }
          },
        ),
        BlocListener<RoomCubit, RoomState>(
          listenWhen: (p, c) =>
              c.status == const StateIsSuccess() &&
              (p.messages != c.messages || p.status != c.status),
          listener: (ctx, s) {
            _basicChatKey.currentState?.onRoomDataChangedForViewport(
              firstUnreadMessageId: s.firstUnreadMessageId,
              messagesEmpty: s.messages.isEmpty,
            );
          },
        ),
      ],
      child: BlocBuilder<RoomCubit, RoomState>(
        buildWhen: (p, c) =>
            p.messages != c.messages ||
            p.factCards
                    .map(
                      (e) =>
                          '${e.id}|${e.pinnedBy}|${e.pinnedByTitle}|${e.status}|${e.visibility}|${e.factText}',
                    )
                    .join() !=
                c.factCards
                    .map(
                      (e) =>
                          '${e.id}|${e.pinnedBy}|${e.pinnedByTitle}|${e.status}|${e.visibility}|${e.factText}',
                    )
                    .join() ||
            p.roomState?.currentLine != c.roomState?.currentLine ||
            p.roomState?.lastRoomMeaningfulChange !=
                c.roomState?.lastRoomMeaningfulChange ||
            p.roomState?.openBlockerId != c.roomState?.openBlockerId ||
            p.roomState?.openBlockerTitle != c.roomState?.openBlockerTitle ||
            p.openCoordinationBlocker?.id != c.openCoordinationBlocker?.id ||
            p.openCoordinationBlocker?.title !=
                c.openCoordinationBlocker?.title ||
            p.openCoordinationBlocker?.status !=
                c.openCoordinationBlocker?.status ||
            p.participants.length != c.participants.length ||
            p.participants
                    .map(
                      (e) =>
                          '${e.userId}|${e.userTitle}|${e.handle}|${e.roomAccess}|${e.nextMoveText}|${e.lastSeenRoomAt?.toIso8601String() ?? ''}',
                    )
                    .join() !=
                c.participants
                    .map(
                      (e) =>
                          '${e.userId}|${e.userTitle}|${e.handle}|${e.roomAccess}|${e.nextMoveText}|${e.lastSeenRoomAt?.toIso8601String() ?? ''}',
                    )
                    .join() ||
            p.unreadAnchorAt != c.unreadAnchorAt ||
            p.pendingMarkSeen != c.pendingMarkSeen ||
            p.status != c.status ||
            p.hasError != c.hasError ||
            p.replyTarget?.id != c.replyTarget?.id ||
            p.pendingQuotedFact?.factCardId !=
                c.pendingQuotedFact?.factCardId ||
            p.beaconStatus != c.beaconStatus ||
            p.myUserId != c.myUserId ||
            p.readWatermarksLoaded != c.readWatermarksLoaded ||
            _readWatermarksFingerprint(p.readWatermarks) !=
                _readWatermarksFingerprint(c.readWatermarks),
        builder: (context, state) {
          final cubit = context.read<RoomCubit>();
          final isThreadMode = state.threadItemId != null;
          final err = state.loadError?.toString() ?? '';
          final canWrite = state.canWriteDiscussion;
          final showPinnedNow =
              !isThreadMode &&
              widget.capabilities.pinnedStrip == RoomPinnedStrip.requestNow &&
              beaconRoomShowsPinnedNow(
                roomState: state.roomState,
                openBlocker: state.openCoordinationBlocker,
              );
          final showPostRoot =
              !isThreadMode &&
              widget.capabilities.pinnedStrip == RoomPinnedStrip.postRoot &&
              (widget.postRoot?.hasStrip ?? false);
          final receiptIndex = RoomReceiptIndex(
            myUserId: state.myUserId,
            watermarks: {
              for (final e in state.readWatermarks.entries)
                e.key: e.value.lastSeenAt,
            },
            pendingLocalIds: const {},
            hasOtherAdmittedDiscussionMember: _hasOtherAdmittedDiscussionMember(
              state,
            ),
          );
          return BasicChatBody(
            key: _basicChatKey,
            receiptIndex: receiptIndex,
            header: showPostRoot
                ? _PinnedPostRootRow(
                    pin: widget.postRoot!,
                    onTap: () => cubit.requestScrollToMessage(
                      widget.postRoot!.messageId,
                    ),
                  )
                : showPinnedNow
                ? _PinnedNowRow(
                    state: state,
                    onEdit: state.canUpdatePlan
                        ? () => unawaited(
                            _showPlanUpdateSheet(context, cubit, l10n),
                          )
                        : null,
                  )
                : null,
            messages: state.messages,
            myProfile: myProfile,
            participants: state.participants,
            isLoading: state.isLoading,
            hasError: state.hasError && state.messages.isEmpty,
            errorText: err,
            firstUnreadIndex: state.firstUnreadIndex,
            firstUnreadMessageId: state.firstUnreadMessageId,
            unreadCount: state.unreadCount,
            onMarkSeenNearBottom: cubit.markReadToBottom,
            onMessageActions: (msg) => _onMessageActionsPressed(
              context,
              cubit,
              l10n,
              myProfile,
              msg,
              isThreadMode: isThreadMode,
            ),
            onReply: canWrite ? cubit.startReplyTo : null,
            onJumpToReply: (id) => unawaited(cubit.jumpToRepliedMessage(id)),
            replyTarget: state.replyTarget,
            onCancelReply: cubit.cancelReply,
            pendingQuotedFact: _pendingQuotedFactCard(state),
            onCancelQuotedFact: cubit.clearPendingQuotedFact,
            onToggleReaction: canWrite
                ? (messageId, emoji) => cubit.toggleReaction(
                    messageId: messageId,
                    emoji: emoji,
                  )
                : null,
            onOpenFileAttachment: (a) => openRoomFileAttachment(
              context,
              l10n,
              a,
            ),
            onVotePoll: canWrite
                ? (messageId, pollingId, variantIds, {score}) => cubit.votePoll(
                    messageId: messageId,
                    pollingId: pollingId,
                    variantIds: variantIds,
                    score: score,
                  )
                : null,
            onBatonRespond: canWrite
                ? (messageId, batonId, canHelp) => cubit.batonRespond(
                    messageId: messageId,
                    batonId: batonId,
                    canHelp: canHelp,
                  )
                : null,
            onSend: widget.enableComposer
                ? (body, uploads) => cubit.sendMessage(
                    body: body,
                    uploads: uploads,
                  )
                : null,
            onSendWithMentions: widget.enableComposer
                ? (body, uploads, mentions) => cubit.sendMessage(
                    body: body,
                    uploads: uploads,
                    explicitMentions: mentions,
                  )
                : null,
            composerReadOnlyHint: canWrite
                ? null
                : l10n.beaconRoomMessageReadOnlyHint,
            onPickFact: canWrite
                ? () async {
                    await showFactPickerSheet(context, cubit: cubit);
                    if (!context.mounted) return;
                    if (cubit.state.pendingQuotedFact != null) {
                      _basicChatKey.currentState?.focusComposer();
                    }
                  }
                : null,
            imageRepository: GetIt.I<ImageRepository>(),
            clipboardImageRepository: GetIt.I<ClipboardImageRepository>(),
            jumpFabHeroTag: 'beacon_room_jump_latest',
            onScrollToPromoteSource: cubit.requestScrollToMessage,
            onOpenCoordinationItem:
                widget.onOpenCoordinationItem ??
                (isThreadMode
                    ? null
                    : (item) => unawaited(
                        openCoordinationItemFromRoom(
                          context,
                          item: item,
                          roomCubit: cubit,
                        ),
                      )),
            pinnedFactForMessage: state.factForRoomMessage,
            pendingJumpMessageId: state.scrollToMessageId,
            capabilities: widget.capabilities,
          );
        },
      ),
    );
  }

  BeaconFactCard? _pendingQuotedFactCard(RoomState state) {
    final quoted = state.pendingQuotedFact;
    if (quoted == null) return null;
    for (final card in state.factCards) {
      if (card.id == quoted.factCardId) return card;
    }
    return BeaconFactCard(
      id: quoted.factCardId,
      beaconId: state.beaconId,
      factText: quoted.factText,
      visibility: quoted.visibility,
      pinnedBy: quoted.pinnedById ?? '',
      pinnedByTitle: quoted.pinnedByTitle,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: quoted.status,
      revisionSeq: quoted.currentSeq,
      attachments: quoted.attachments,
    );
  }

  void _quoteFactInChat(RoomCubit cubit, BeaconFactCard fact) {
    cubit.setPendingQuotedFact(fact);
    _basicChatKey.currentState?.focusComposer();
  }

  Future<void> _pinOrManageFactForMessage(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
    BeaconFactCard? pf,
  ) async {
    if (pf != null) {
      await showFactActionsSheet(
        context,
        cubit: cubit,
        fact: pf,
        onQuoteInChat: (f) => _quoteFactInChat(cubit, f),
      );
      return;
    }
    final text = _pinFactTextForMessage(message, l10n);
    if (text.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.beaconRoomPinFactDisabledEmpty)),
      );
      return;
    }
    await _showPinFactChoices(context, cubit, l10n, message, text);
  }

  RoomReceiptIndex _receiptIndexFor(RoomState state) => RoomReceiptIndex(
    myUserId: state.myUserId,
    watermarks: {
      for (final e in state.readWatermarks.entries) e.key: e.value.lastSeenAt,
    },
    pendingLocalIds: const {},
    hasOtherAdmittedDiscussionMember: _hasOtherAdmittedDiscussionMember(state),
  );

  bool _hasOtherAdmittedDiscussionMember(RoomState state) {
    if (!state.participantsLoaded) {
      return false;
    }
    return state.participants.any(
      (p) =>
          p.userId != state.myUserId && p.roomAccess == RoomAccessBits.admitted,
    );
  }

  String _readBySubtitle(
    L10n l10n,
    List<BeaconParticipant> participants,
    List<String> readerIds,
    Profile viewer,
  ) {
    const maxNames = 3;
    final names = readerIds
        .take(maxNames)
        .map(
          (id) => participantDisplayLabel(
            participants,
            id,
            l10n.unknownPerson,
            viewerProfile: viewer,
          ),
        )
        .toList(growable: false);
    final joined = names.join(', ');
    final extra = readerIds.length - maxNames;
    if (extra > 0) {
      return '$joined, ${l10n.beaconRoomReadByMore(extra)}';
    }
    return joined;
  }

  List<Widget> _messageActionsReadByRows({
    required BuildContext sheetContext,
    required BuildContext hostContext,
    required RoomCubit cubit,
    required L10n l10n,
    required Profile viewer,
    required RoomMessage message,
  }) {
    final receipt = _receiptIndexFor(cubit.state).receiptFor(message);
    if (receipt == null || receipt.state == RoomMessageReceiptState.pending) {
      return const [];
    }

    final theme = Theme.of(sheetContext);
    final tt = sheetContext.tt;
    final participants = cubit.state.participants;
    final receiptIndex = _receiptIndexFor(cubit.state);

    if (receipt.state == RoomMessageReceiptState.sent) {
      return [
        ListTile(
          title: Text(l10n.beaconRoomReadByTitle),
          subtitle: Text(
            l10n.beaconRoomReadByNobodyYet,
            style: theme.textTheme.bodyMedium?.copyWith(color: tt.textMuted),
          ),
        ),
      ];
    }

    final readerIds = receipt.readerIds;
    final stackProfiles = readerIds
        .take(3)
        .map(
          (id) => profileForParticipant(
            participants,
            id,
            viewerProfile: viewer,
          ),
        )
        .toList(growable: false);

    return [
      ListTile(
        leading: Icon(Icons.done_all, color: tt.info),
        title: Text(l10n.beaconRoomReadByTitle),
        subtitle: Text(
          _readBySubtitle(l10n, participants, readerIds, viewer),
        ),
        trailing: TenturaAvatarStack(profiles: stackProfiles),
        onTap: () {
          final readers = readerIds
              .map((id) {
                final readAt = receiptIndex.readerLastSeenAt(
                  id,
                  message.createdAt,
                );
                if (readAt == null) {
                  return null;
                }
                return RoomReaderEntry(
                  profile: profileForParticipant(
                    participants,
                    id,
                    viewerProfile: viewer,
                  ),
                  readAt: readAt,
                );
              })
              .whereType<RoomReaderEntry>()
              .toList(growable: false);
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!hostContext.mounted) {
              return;
            }
            unawaited(showRoomReadersSheet(hostContext, readers: readers));
          });
        },
      ),
    ];
  }

  static Set<String> _viewerReactionEmojis(RoomMessage m) {
    final raw = m.myReaction;
    if (raw == null || raw.trim().isEmpty) return {};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  void _onMessageActionsPressed(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message, {
    bool isThreadMode = false,
  }) {
    final canWrite = cubit.state.canWriteDiscussion;
    final pf = cubit.state.factForRoomMessage(message);
    final caps = widget.capabilities;
    final showFactInMenu =
        caps.facts && !isThreadMode && !_suppressesRichMessageActions(message);
    final isOwnMessage = message.authorId == viewer.id;
    final viewerReactions = _viewerReactionEmojis(message);
    // Already-linked messages can be opened/resolved but never re-promoted;
    // only plain, non-system messages offer the "Turn into…" verbs.
    final linkedItem = message.linkedCoordinationItem;
    final showCreateChild =
        caps.coordinationItems &&
        canWrite &&
        !isThreadMode &&
        linkedItem == null &&
        !_suppressesRichMessageActions(message);
    final hasBodyText = message.body.trim().isNotEmpty;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        // useRootNavigator: true is required on Web.
        //
        // BeaconViewScreen PopScope on non-NOW surfaces intercepts browser
        // back until the user returns to NOW. Flutter Web implements this by
        // injecting a sentinel history entry via
        // SystemNavigator. When showModalBottomSheet opens under the *same*
        // Navigator as that PopScope (the default, useRootNavigator: false),
        // the sentinel and the modal's route lifecycle interact: after the
        // sheet is dismissed the Web platform's hit-test / gesture-delivery
        // machinery stops forwarding taps to the AppBar back button, making
        // exit unreachable even though the room UI is still visible.
        //
        // Opening the sheet under the root Navigator places it above the
        // PopScope's scope, decoupling its lifecycle from the sentinel and
        // restoring normal tap delivery once the sheet closes.
        useRootNavigator: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final tt = ctx.tt;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tt.contentMaxWidth ?? double.infinity,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          left: tt.screenHPadding,
                          right: tt.screenHPadding,
                          top: tt.rowGap,
                        ),
                        child: Text(
                          l10n.beaconRoomMessageActionsTitle,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      if (canWrite)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tt.screenHPadding,
                          ),
                          child: ReactionQuickPicker(
                            selected: viewerReactions,
                            onPick: (emoji) {
                              Navigator.pop(ctx);
                              unawaited(
                                cubit.toggleReaction(
                                  messageId: message.id,
                                  emoji: emoji,
                                ),
                              );
                            },
                          ),
                        ),
                      if (isOwnMessage)
                        ..._messageActionsReadByRows(
                          sheetContext: ctx,
                          hostContext: context,
                          cubit: cubit,
                          l10n: l10n,
                          viewer: viewer,
                          message: message,
                        ),
                      if (canWrite && RoomCubit.canReplyTo(message))
                        ListTile(
                          leading: const Icon(Icons.reply_outlined),
                          title: Text(l10n.beaconRoomActionReply),
                          onTap: () {
                            Navigator.pop(ctx);
                            cubit.startReplyTo(message);
                          },
                        ),
                      // ── Coordination: turn a plain message into an item … ──
                      if (showCreateChild) ...[
                        Padding(
                          padding: EdgeInsets.only(
                            left: tt.screenHPadding,
                            right: tt.screenHPadding,
                            top: tt.rowGap,
                          ),
                          child: Text(
                            l10n.beaconRoomActionTurnInto,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.subdirectory_arrow_right_outlined,
                          ),
                          title: Text(l10n.beaconCreateChildRequest),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openChildRequestComposerFromMessage(
                              context,
                              cubit,
                              message,
                            );
                          },
                        ),
                        if (caps.plan)
                          ListTile(
                            leading: const Icon(Icons.edit_note_outlined),
                            title: Text(
                              l10n.beaconRoomActionUpdatePlanFromMessage,
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(
                                _showUpdatePlanFromMessageSheet(
                                  context,
                                  cubit,
                                  l10n,
                                  message,
                                ),
                              );
                            },
                          ),
                      ],
                      // ── …or open / resolve an already-linked item. ──
                      if (caps.plan &&
                          linkedItem != null &&
                          linkedItem.kind == CoordinationItemKind.plan &&
                          (!isThreadMode ||
                              widget.onOpenCoordinationItem != null)) ...[
                        ListTile(
                          leading: const Icon(
                            Icons.subdirectory_arrow_left_outlined,
                          ),
                          title: Text(l10n.beaconRoomActionJumpToPlan),
                          onTap: () {
                            Navigator.pop(ctx);
                            final open = widget.onOpenCoordinationItem;
                            if (open != null) {
                              open(linkedItem);
                              return;
                            }
                            unawaited(
                              openCoordinationItemFromRoom(
                                context,
                                item: linkedItem,
                                roomCubit: cubit,
                              ),
                            );
                          },
                        ),
                      ],
                      // ── Fact pin (state-aware). ──
                      if (canWrite && showFactInMenu && pf == null)
                        ListTile(
                          leading: const Icon(Icons.fact_check_outlined),
                          title: Text(l10n.beaconRoomActionPinFact),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(
                              _pinOrManageFactForMessage(
                                context,
                                cubit,
                                l10n,
                                message,
                                null,
                              ),
                            );
                          },
                        ),
                      if (showFactInMenu && pf != null)
                        ListTile(
                          leading: const Icon(Icons.fact_check_outlined),
                          title: Text(l10n.beaconRoomActionViewPinnedFact),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(
                              showFactActionsSheet(
                                context,
                                cubit: cubit,
                                fact: pf,
                                onQuoteInChat: (f) =>
                                    _quoteFactInChat(cubit, f),
                              ),
                            );
                          },
                        ),
                      if (canWrite && showFactInMenu && pf != null)
                        ListTile(
                          leading: Icon(
                            Icons.push_pin_outlined,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            l10n.beaconRoomFactCardActionRemove,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(
                              _confirmUnpinFactFromMessage(
                                context,
                                cubit,
                                l10n,
                                pf,
                              ),
                            );
                          },
                        ),
                      // ── Generic utilities. ──
                      if (hasBodyText)
                        ListTile(
                          leading: const Icon(Icons.copy_outlined),
                          title: Text(l10n.beaconRoomActionCopyText),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_copyMessageText(context, l10n, message));
                          },
                        ),
                      // ── Destructive (own message), divided off and last. ──
                      if (canWrite &&
                          isOwnMessage &&
                          !isThreadMode &&
                          !_suppressesRichMessageActions(message)) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l10n.beaconRoomActionEditMessage),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(
                              _showEditMessageSheet(
                                context,
                                cubit,
                                l10n,
                                message,
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            l10n.beaconRoomActionDeleteMessage,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(
                              _confirmDeleteMessage(
                                context,
                                cubit,
                                l10n,
                                message,
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmUnpinFactFromMessage(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    BeaconFactCard fact,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.beaconRoomFactCardRemoveConfirmTitle),
        content: Text(l10n.beaconRoomFactCardRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.beaconRoomFactCardRemoveConfirmAction),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await cubit.removeFact(factCardId: fact.id);
    }
  }

  Future<void> _confirmDeleteMessage(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final isPostRoot = widget.postRoot?.messageId == message.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isPostRoot
              ? l10n.postDeleteConfirmTitle
              : l10n.beaconRoomDeleteMessageConfirmTitle,
        ),
        content: Text(
          isPostRoot
              ? l10n.postDeleteConfirmBody
              : l10n.beaconRoomDeleteMessageConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.beaconRoomDeleteMessageConfirmAction),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await cubit.deleteMessage(messageId: message.id);
    }
  }

  Future<void> _showPlanUpdateSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
  ) => showBeaconRoomUpdatePlanSheet(context, cubit, l10n);

  Future<void> _showEditMessageSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final newBody = await showTenturaAdaptiveSheet<String>(
      context: context,
      useRootNavigator: true,
      enableDrag: false,
      builder: (ctx) => _BeaconRoomTextBottomSheet(
        title: l10n.beaconRoomActionEditMessage,
        hintText: l10n.beaconRoomMessageHint,
        initialText: message.body,
      ),
    );
    if (newBody == null || !context.mounted) return;
    _basicChatKey.currentState?.focusComposer();
    if (newBody.isEmpty) return;
    if (newBody == message.body) return;
    await cubit.editMessage(
      messageId: message.id,
      newBody: newBody,
    );
  }

  Future<void> _showPinFactChoices(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
    String text,
  ) async {
    await showTenturaAdaptiveSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: ctx.tt.screenHPadding,
                right: ctx.tt.screenHPadding,
                top: ctx.tt.rowGap,
              ),
              child: Text(
                l10n.beaconRoomPinFactTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              title: Text(l10n.beaconRoomPinFactPublic),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(
                  cubit.pinFactFromMessage(
                    sourceMessageId: message.id,
                    factText: text,
                    visibility: BeaconFactCardVisibilityBits.public,
                  ),
                );
              },
            ),
            ListTile(
              title: Text(l10n.beaconRoomPinFactRoomOnly),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(
                  cubit.pinFactFromMessage(
                    sourceMessageId: message.id,
                    factText: text,
                    visibility: BeaconFactCardVisibilityBits.room,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openChildRequestComposerFromMessage(
    BuildContext context,
    RoomCubit cubit,
    RoomMessage message,
  ) {
    unawaited(
      context.router.push(
        BeaconCreateRoute(
          parentBeaconId: cubit.state.beaconId,
          sourceMessageId: message.id,
        ),
      ),
    );
  }

  Future<void> _copyMessageText(
    BuildContext context,
    L10n l10n,
    RoomMessage message,
  ) async {
    final ok = await copyTextToClipboard(message.body.trim());
    if (!ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.beaconRoomCopiedToClipboard)),
    );
  }

  Future<void> _showUpdatePlanFromMessageSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final body = message.body.trim();
    if (body.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.beaconRoomPinFactDisabledEmpty)),
      );
      return;
    }
    final initialText = body.length > kBeaconRoomCurrentLineMaxLength
        ? body.substring(0, kBeaconRoomCurrentLineMaxLength)
        : body;
    final plan = await showTenturaAdaptiveSheet<String>(
      context: context,
      useRootNavigator: true,
      enableDrag: false,
      builder: (ctx) => _BeaconRoomTextBottomSheet(
        title: l10n.beaconRoomActionUpdatePlan,
        hintText: l10n.beaconRoomStripCurrentLineLabel,
        initialText: initialText,
        maxLength: kBeaconRoomCurrentLineMaxLength,
      ),
    );
    if (plan == null || plan.isEmpty || !context.mounted) return;
    await cubit.updatePlan(plan);
    widget.onCoordinationSaved?.call();
  }
}

/// Standalone "Update plan" text sheet
/// on the pinned-now strip and the beacon app-bar overflow menu.
Future<void> showBeaconRoomUpdatePlanSheet(
  BuildContext context,
  RoomCubit cubit,
  L10n l10n,
) async {
  final plan = await showTenturaAdaptiveSheet<String>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    builder: (ctx) => _BeaconRoomTextBottomSheet(
      title: l10n.beaconRoomActionUpdatePlan,
      hintText: l10n.beaconRoomStripCurrentLineLabel,
      initialText: cubit.state.roomState?.currentLine ?? '',
      maxLength: kBeaconRoomCurrentLineMaxLength,
    ),
  );
  if (plan == null || !context.mounted) return;
  await cubit.updatePlan(plan);
}

class _BeaconRoomTextBottomSheet extends StatefulWidget {
  const _BeaconRoomTextBottomSheet({
    required this.title,
    required this.hintText,
    this.initialText = '',
    this.maxLength,
  });

  final String title;
  final String hintText;
  final String initialText;
  final int? maxLength;

  @override
  State<_BeaconRoomTextBottomSheet> createState() =>
      _BeaconRoomTextBottomSheetState();
}

class _BeaconRoomTextBottomSheetState
    extends State<_BeaconRoomTextBottomSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text.trim() != widget.initialText.trim();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.sectionGap,
          bottom: bottom + tt.sectionGap,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              TextField(
                controller: _controller,
                maxLines: widget.maxLength != null ? 2 : 6,
                minLines: widget.maxLength != null ? 1 : 3,
                maxLength: widget.maxLength,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: tt.sectionGap),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                child: Text(MaterialLocalizations.of(context).saveButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedNowRow extends StatelessWidget {
  const _PinnedNowRow({
    required this.state,
    this.onEdit,
  });

  final RoomState state;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final nowDisplay = beaconRoomHudNowDisplay(
      l10n,
      roomState: state.roomState,
      openBlocker: state.openCoordinationBlocker,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tt.surface,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              border: Border.all(color: tt.borderSubtle),
            ),
            child: Padding(
              padding: tt.cardPadding,
              child: HudLabeledMultiline(
                leadingIcon: BeaconHudRowIcons.now,
                semanticsLabel: l10n.beaconHudNowLabel,
                text: nowDisplay.primaryText,
                subline: nowDisplay.blockerText,
                mutedColor: tt.textMuted,
                isPlaceholder: nowDisplay.isPlaceholder,
                onEdit: onEdit,
                editSemanticLabel: l10n.beaconHudEditNowLine,
                primaryMaxLines: 1,
                showTruncationHint: false,
              ),
            ),
          ),
        ),
        const TenturaHairlineDivider(),
      ],
    );
  }
}

/// Post rooms: the root excerpt (tap scrolls to the root message) and, for a
/// recipient the Post was forwarded to, who forwarded it and their note.
class _PinnedPostRootRow extends StatelessWidget {
  const _PinnedPostRootRow({required this.pin, required this.onTap});

  final RoomPostRootPin pin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final forwardedLine = pin.forwardedBy.isEmpty
        ? null
        : pin.forwardNote.isEmpty
        ? l10n.postForwardedByLineNoNote(pin.forwardedBy)
        : l10n.postForwardedByLine(pin.forwardedBy, pin.forwardNote);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.rowGap,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: Material(
        color: tt.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tt.cardRadius),
          side: BorderSide(color: tt.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: tt.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.push_pin_outlined, size: tt.iconSize),
                SizedBox(width: tt.iconTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.bodySmall(tt.text),
                      ),
                      if (forwardedLine != null)
                        Text(
                          forwardedLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
