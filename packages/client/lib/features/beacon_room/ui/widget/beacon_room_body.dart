import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/features/coordination_item/ui/widget/ask_composer_fields.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_staleness_picker.dart';

import '../bloc/room_cubit.dart';
import '../coordination_room_navigation.dart';
import 'beacon_room_promise_sheet.dart';
import 'fact_actions_sheet.dart';
import 'room_file_attachment_open.dart';
import 'room_reaction_picker.dart';

/// Body-only room UI (message list + composer); expects [RoomCubit] above.
class BeaconRoomBody extends StatefulWidget {
  const BeaconRoomBody({
    super.key,
    this.enableComposer = true,
  });

  final bool enableComposer;

  @override
  State<BeaconRoomBody> createState() => _BeaconRoomBodyState();
}

class _BeaconRoomBodyState extends State<BeaconRoomBody> {
  final _basicChatKey = GlobalKey<BasicChatBodyState>();

  bool _suppressesRichMessageActions(RoomMessage message) =>
      message.semanticMarker == BeaconRoomSemanticMarker.blocker ||
      message.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
      message.semanticMarker == BeaconRoomSemanticMarker.done;

  /// Non-empty text for [BeaconFactCard]; attachments use names or [L10n.beaconRoomPinFactAttachmentBodyFallback].
  String _pinFactTextForMessage(RoomMessage message, L10n l10n) {
    final body = message.body.trim();
    if (body.isNotEmpty) {
      return body;
    }
    if (message.attachments.isEmpty) {
      return '';
    }
    final names = <String>[];
    for (final a in message.attachments) {
      final n = a.fileName.trim();
      if (n.isNotEmpty) {
        names.add(n);
      }
    }
    if (names.isNotEmpty) {
      const maxNames = 3;
      if (names.length <= maxNames) {
        return names.join(', ');
      }
      return '${names.take(maxNames).join(', ')}…';
    }
    return l10n.beaconRoomPinFactAttachmentBodyFallback;
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
              final ok =
                  await (_basicChatKey.currentState?.scrollToMessage(id) ??
                      Future.value(false));
              if (ctx.mounted && ok) {
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
                          '${e.id}|${e.pinnedBy}|${e.pinnedByTitle}|${e.status}|${e.factText}',
                    )
                    .join() !=
                c.factCards
                    .map(
                      (e) =>
                          '${e.id}|${e.pinnedBy}|${e.pinnedByTitle}|${e.status}|${e.factText}',
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
                          '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.lastSeenRoomAt?.toIso8601String() ?? ''}',
                    )
                    .join() !=
                c.participants
                    .map(
                      (e) =>
                          '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.lastSeenRoomAt?.toIso8601String() ?? ''}',
                    )
                    .join() ||
            p.unreadAnchorAt != c.unreadAnchorAt ||
            p.pendingMarkSeen != c.pendingMarkSeen ||
            p.status != c.status ||
            p.hasError != c.hasError,
        builder: (context, state) {
          final cubit = context.read<RoomCubit>();
          final isThreadMode = state.threadItemId != null;
          final err = state.status is StateHasError
              ? (state.status as StateHasError).error.toString()
              : '';
          final showPinnedNow =
              !isThreadMode &&
              beaconRoomShowsPinnedNow(
                roomState: state.roomState,
                openBlocker: state.openCoordinationBlocker,
              );
          return BasicChatBody(
            key: _basicChatKey,
            header: showPinnedNow
                ? _PinnedNowRow(
                    state: state,
                    onEdit: _roomCanCreatePromise(cubit)
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
            onToggleReaction: (messageId, emoji) => cubit.toggleReaction(
              messageId: messageId,
              emoji: emoji,
            ),
            onOpenFileAttachment: (a) => openRoomFileAttachment(
              context,
              l10n,
              a,
            ),
            onVotePoll: (messageId, pollingId, variantIds, {score}) =>
                cubit.votePoll(
                  messageId: messageId,
                  pollingId: pollingId,
                  variantIds: variantIds,
                  score: score,
                ),
            onSend: widget.enableComposer
                ? (body, uploads) => cubit.sendMessage(
                    body: body,
                    uploads: uploads,
                  )
                : null,
            imageRepository: GetIt.I<ImageRepository>(),
            jumpFabHeroTag: 'beacon_room_jump_latest',
            onScrollToPromoteSource: cubit.requestScrollToMessage,
            onOpenCoordinationItem: isThreadMode
                ? null
                : (item) => unawaited(
                    openCoordinationItemFromRoom(
                      context,
                      item: item,
                      roomCubit: cubit,
                    ),
                  ),
          );
        },
      ),
    );
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
    final pf = cubit.state.factForRoomMessage(message);
    final showFactInMenu =
        !isThreadMode && !_suppressesRichMessageActions(message);
    final isOwnMessage = message.authorId == viewer.id;
    final viewerReactions = _viewerReactionEmojis(message);
    // Already-linked messages can be opened/resolved but never re-promoted;
    // only plain, non-system messages offer the "Turn into…" verbs.
    final linkedItem = message.linkedCoordinationItem;
    final showTurnInto =
        !isThreadMode &&
        linkedItem == null &&
        !_suppressesRichMessageActions(message);
    final canCreatePromise = _roomCanCreatePromise(cubit);
    final hasBodyText = message.body.trim().isNotEmpty;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        // useRootNavigator: true is required on Web.
        //
        // BeaconViewScreen wraps its room surface in PopScope(canPop: false)
        // so that the browser back-button can be intercepted. Flutter Web
        // implements this by injecting a sentinel history entry via
        // SystemNavigator. When showModalBottomSheet opens under the *same*
        // Navigator as that PopScope (the default, useRootNavigator: false),
        // the sentinel and the modal's route lifecycle interact: after the
        // sheet is dismissed the Web platform's hit-test / gesture-delivery
        // machinery stops forwarding taps to the AppBar back button, making
        // _exitRoomSurface unreachable even though the room UI is still
        // visible and the URL still contains ?tab=room.
        //
        // Opening the sheet under the root Navigator places it above the
        // PopScope's scope, decoupling its lifecycle from the sentinel and
        // restoring normal tap delivery once the sheet closes.
        useRootNavigator: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final tt = ctx.tt;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: kPaddingH.add(kPaddingSmallT),
                    child: Text(
                      l10n.beaconRoomMessageActionsTitle,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: kPaddingH,
                    child: Wrap(
                      spacing: kSpacingSmall,
                      runSpacing: kSpacingSmall,
                      children: [
                        for (final emoji in kBeaconRoomReactionPickerEmojis)
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(
                                cubit.toggleReaction(
                                  messageId: message.id,
                                  emoji: emoji,
                                ),
                              );
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: viewerReactions.contains(emoji)
                                      ? tt.skyBorder
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  emoji,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── Coordination: turn a plain message into an item … ──
                  if (showTurnInto) ...[
                    Padding(
                      padding: kPaddingH.add(kPaddingSmallT),
                      child: Text(
                        l10n.beaconRoomActionTurnInto,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (canCreatePromise)
                      ListTile(
                        leading: const Icon(Icons.front_hand_outlined),
                        title: Text(l10n.coordinationCreatePromiseFromMessage),
                        onTap: () {
                          Navigator.pop(ctx);
                          _startPromiseFromMessage(context, cubit, message);
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text(l10n.beaconRoomActionMarkAsk),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(
                          _showMarkAskSheet(
                            context,
                            cubit,
                            l10n,
                            viewer,
                            message,
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.report_problem_outlined),
                      title: Text(l10n.beaconRoomActionMarkBlocker),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(
                          _showMarkBlockerSheet(
                            context,
                            cubit,
                            l10n,
                            viewer,
                            message,
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_note_outlined),
                      title: Text(l10n.beaconRoomActionUpdatePlanFromMessage),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(
                          _showUpdatePlanFromMessageSheet(
                            context,
                            cubit,
                            l10n,
                            viewer,
                            message,
                          ),
                        );
                      },
                    ),
                  ],
                  // ── …or open / resolve an already-linked item. ──
                  if (linkedItem != null && !isThreadMode) ...[
                    ListTile(
                      leading: Icon(
                        planItemSuppressesItemDiscussion(linkedItem)
                            ? Icons.subdirectory_arrow_left_outlined
                            : Icons.forum_outlined,
                      ),
                      title: Text(
                        planItemSuppressesItemDiscussion(linkedItem)
                            ? l10n.beaconRoomActionJumpToPlan
                            : l10n.beaconRoomActionOpenThread,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(
                          openCoordinationItemFromRoom(
                            context,
                            item: linkedItem,
                            roomCubit: cubit,
                          ),
                        );
                      },
                    ),
                    if (linkedItem.kind == CoordinationItemKind.blocker &&
                        linkedItem.status == CoordinationItemStatus.open)
                      ListTile(
                        leading: const Icon(Icons.task_alt_outlined),
                        title: Text(l10n.beaconRoomActionResolveBlocker),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(
                            cubit.resolveCoordinationBlocker(
                              itemId: linkedItem.id,
                            ),
                          );
                        },
                      ),
                  ],
                  // ── Fact pin (state-aware). ──
                  if (showFactInMenu && pf == null)
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
                          ),
                        );
                      },
                    ),
                  if (showFactInMenu && pf != null)
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
                  if (isOwnMessage && showFactInMenu) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l10n.beaconRoomActionEditMessage),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(
                          _showEditMessageSheet(context, cubit, l10n, message),
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
                          _confirmDeleteMessage(context, cubit, l10n, message),
                        );
                      },
                    ),
                  ],
                ],
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.beaconRoomDeleteMessageConfirmTitle),
        content: Text(l10n.beaconRoomDeleteMessageConfirmBody),
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
      // Keep this sheet modal while the keyboard animates; barrier dismissal
      // here is the path that was collapsing the editor on mobile.
      isDismissible: false,
      builder: (ctx) => _BeaconRoomTextBottomSheet(
        title: l10n.beaconRoomActionEditMessage,
        hintText: l10n.beaconRoomMessageHint,
        initialText: message.body,
      ),
    );
    if (newBody == null || !context.mounted) return;
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

  bool _roomCanCreatePromise(RoomCubit cubit) {
    final myUserId = cubit.state.myUserId;
    if (myUserId.isEmpty) return false;
    BeaconParticipant? myParticipant;
    for (final p in cubit.state.participants) {
      if (p.userId == myUserId) {
        myParticipant = p;
        break;
      }
    }
    if (myParticipant == null) return false;
    if (myParticipant.role == BeaconParticipantRoleBits.author ||
        myParticipant.role == BeaconParticipantRoleBits.steward) {
      return true;
    }
    return myParticipant.roomAccess == RoomAccessBits.admitted;
  }

  /// Opens the promise composer seeded from [message] (Turn into ▸ Promise).
  void _startPromiseFromMessage(
    BuildContext context,
    RoomCubit cubit,
    RoomMessage message,
  ) {
    final myUserId = cubit.state.myUserId;
    final myRole = cubit.state.participants
        .where((p) => p.userId == myUserId)
        .firstOrNull
        ?.role;
    final isAuthorOrSteward =
        myRole == BeaconParticipantRoleBits.author ||
        myRole == BeaconParticipantRoleBits.steward;
    unawaited(
      showBeaconRoomPromiseSheet(
        context,
        beaconId: cubit.state.beaconId,
        participants: cubit.state.participants,
        myUserId: myUserId,
        isAuthorOrSteward: isAuthorOrSteward,
        seed: AskComposerSeed.fromMessage(
          messageId: message.id,
          messageBody: message.body,
        ),
      ),
    );
  }

  Future<void> _copyMessageText(
    BuildContext context,
    L10n l10n,
    RoomMessage message,
  ) async {
    await Clipboard.setData(ClipboardData(text: message.body.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.beaconRoomCopiedToClipboard)),
    );
  }

  List<BeaconParticipant> _admittedParticipantsForPromote(RoomCubit cubit) {
    final myUserId = cubit.state.myUserId;
    final myParticipantRole = cubit.state.participants
        .where((p) => p.userId == myUserId)
        .firstOrNull
        ?.role;
    final isAuthorOrSteward =
        myParticipantRole == BeaconParticipantRoleBits.author ||
        myParticipantRole == BeaconParticipantRoleBits.steward;
    return isAuthorOrSteward
        ? cubit.state.participants
              .where(
                (p) =>
                    p.roomAccess == RoomAccessBits.admitted ||
                    p.status == BeaconParticipantStatusBits.candidate ||
                    p.status == BeaconParticipantStatusBits.offeredHelp,
              )
              .toList()
        : cubit.state.participants
              .where((p) => p.roomAccess == RoomAccessBits.admitted)
              .toList();
  }

  Future<
    ({String title, String body, String targetUserId, int? staleAfterDays})?
  >
  _showPromoteFieldsDialog({
    required BuildContext context,
    required L10n l10n,
    required Profile viewer,
    required RoomCubit cubit,
    required String dialogTitle,
    required String messageBody,
    bool includeStalenessPicker = false,
  }) async {
    final admitted = _admittedParticipantsForPromote(cubit);
    if (admitted.isEmpty) return null;

    final titleController = TextEditingController();
    final bodyController = TextEditingController(text: messageBody);
    var targetUserId = viewer.id;
    if (!admitted.any((p) => p.userId == targetUserId)) {
      targetUserId = admitted.first.userId;
    }
    var staleDays = CoordinationItem.defaultStaleDays;

    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return StatefulBuilder(
            builder: (ctx, setState) => Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: AlertDialog(
                title: Text(dialogTitle),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: l10n.coordinationPromoteTitleHint,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: kSpacingSmall),
                      TextField(
                        controller: bodyController,
                        decoration: InputDecoration(
                          hintText: l10n.coordinationPromoteBodyHint,
                        ),
                        maxLines: 4,
                        autofocus: messageBody.isEmpty,
                      ),
                      const SizedBox(height: kSpacingSmall),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(targetUserId),
                        initialValue: targetUserId,
                        decoration: InputDecoration(
                          labelText: l10n.beaconRoomNeedInfoPickTarget,
                        ),
                        items: [
                          for (final p in admitted)
                            DropdownMenuItem(
                              value: p.userId,
                              child: Text(
                                _needInfoTargetLabel(l10n, viewer, p),
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => targetUserId = v ?? targetUserId),
                      ),
                      if (includeStalenessPicker) ...[
                        const SizedBox(height: kSpacingSmall),
                        CoordinationStalenessPicker(
                          l10n: l10n,
                          selectedDays: staleDays,
                          onSelected: (days) =>
                              setState(() => staleDays = days),
                        ),
                      ] else ...[
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          l10n.coordinationStalenessDefaultHint,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      MaterialLocalizations.of(ctx).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (ok != true) return null;
      final body = bodyController.text.trim();
      if (body.isEmpty) return null;
      final titleRaw = titleController.text.trim();
      final title = titleRaw.isEmpty ? body : titleRaw;
      return (
        title: title,
        body: body,
        targetUserId: targetUserId,
        staleAfterDays: includeStalenessPicker ? staleDays : null,
      );
    } finally {
      titleController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _showUpdatePlanFromMessageSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final fields = await _showPromoteFieldsDialog(
      context: context,
      l10n: l10n,
      viewer: viewer,
      cubit: cubit,
      dialogTitle: l10n.beaconRoomActionUpdatePlan,
      messageBody: message.body.trim(),
    );
    if (fields == null || !context.mounted) return;
    await cubit.updatePlan(
      fields.title,
      body: fields.body,
      targetPersonId: fields.targetUserId,
      linkedMessageId: message.id,
    );
  }

  Future<void> _showMarkAskSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final fields = await _showPromoteFieldsDialog(
      context: context,
      l10n: l10n,
      viewer: viewer,
      cubit: cubit,
      dialogTitle: l10n.coordinationMarkAskTitle,
      messageBody: message.body.trim(),
      includeStalenessPicker: true,
    );
    if (fields == null || !context.mounted) return;
    await cubit.markAskFromMessage(
      messageId: message.id,
      title: fields.title,
      targetPersonId: fields.targetUserId,
      body: fields.body,
      staleAfterDays: fields.staleAfterDays,
    );
  }

  Future<void> _showMarkBlockerSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final fields = await _showPromoteFieldsDialog(
      context: context,
      l10n: l10n,
      viewer: viewer,
      cubit: cubit,
      dialogTitle: l10n.beaconRoomActionMarkBlocker,
      messageBody: message.body.trim(),
      includeStalenessPicker: true,
    );
    if (fields == null || !context.mounted) return;
    await cubit.markBlockerFromMessage(
      messageId: message.id,
      title: fields.title,
      body: fields.body,
      targetPersonId: fields.targetUserId,
      staleAfterDays: fields.staleAfterDays,
    );
  }

  String _needInfoTargetLabel(L10n l10n, Profile viewer, BeaconParticipant p) {
    if (p.userId == viewer.id) {
      return l10n.labelYou;
    }
    final t = p.userTitle.trim();
    if (t.isNotEmpty) {
      return t;
    }
    return p.userId.length <= 16 ? p.userId : '${p.userId.substring(0, 14)}…';
  }
}

/// Standalone "Update plan" text sheet — shared by the per-message edit affordance
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
    // The edit sheet must stay open across keyboard resize on mobile.
    isDismissible: false,
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

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
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
