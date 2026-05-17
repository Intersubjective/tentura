import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'package:tentura/features/polling/ui/widget/polling_question_input.dart';
import 'package:tentura/features/polling/ui/widget/polling_variant_input.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon_view/ui/widget/beacon_prepared_ask_sheet.dart';
import 'package:tentura/features/coordination_item/ui/widget/ask_composer_fields.dart';

import '../bloc/room_cubit.dart';
import 'beacon_room_self_ask_sheet.dart';
import 'fact_actions_sheet.dart';
import 'room_file_attachment_open.dart';
import 'room_reaction_picker.dart';

/// Body-only room UI (message list + composer); expects [RoomCubit] above.
class BeaconRoomBody extends StatefulWidget {
  const BeaconRoomBody({super.key});

  @override
  State<BeaconRoomBody> createState() => _BeaconRoomBodyState();
}

class _BeaconRoomBodyState extends State<BeaconRoomBody> {
  final _basicChatKey = GlobalKey<BasicChatBodyState>();

  bool _roomMessageIsCoordinationStateCard(RoomMessage message) =>
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
              final ok = await (_basicChatKey.currentState?.scrollToMessage(id) ??
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
            p.roomState?.currentPlan != c.roomState?.currentPlan ||
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
          final err = state.status is StateHasError
              ? (state.status as StateHasError).error.toString()
              : '';
          final plan = state.roomState?.currentPlan.trim() ?? '';
          return BasicChatBody(
            key: _basicChatKey,
            header: plan.isEmpty ? null : _PinnedPlanCard(plan: plan),
            messages: state.messages,
            myProfile: myProfile,
            participants: state.participants,
            isLoading: state.isLoading,
            hasError: state.hasError && state.messages.isEmpty,
            errorText: err,
            firstUnreadIndex: state.firstUnreadIndex,
            unreadCount: state.unreadCount,
            onMarkSeenNearBottom: cubit.markSeenNowIfNeeded,
            onMessageActions: (msg) => _onMessageActionsPressed(
              context,
              cubit,
              l10n,
              myProfile,
              msg,
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
            onSend: (body, uploads) => cubit.sendMessage(
              body: body,
              uploads: uploads,
            ),
            showPollButton: true,
            onOpenPollSheet: (ctx) => _showCreatePollSheet(ctx, cubit),
            imageRepository: GetIt.I<ImageRepository>(),
            jumpFabHeroTag: 'beacon_room_jump_latest',
            onScrollToPromoteSource: cubit.requestScrollToMessage,
          );
        },
      ),
    );
  }

  Future<void> _showCreatePollSheet(
    BuildContext context,
    RoomCubit cubit,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PollCreateSheet(cubit: cubit),
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
    RoomMessage message,
  ) {
    final pf = cubit.state.factForRoomMessage(message);
    final showFactInMenu = !_roomMessageIsCoordinationStateCard(message);
    final isOwnMessage = message.authorId == viewer.id;
    final viewerReactions = _viewerReactionEmojis(message);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
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
                  if (isOwnMessage && showFactInMenu)
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
                  if (isOwnMessage && showFactInMenu)
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
                  ListTile(
                    leading: const Icon(Icons.edit_note_outlined),
                    title: Text(l10n.beaconRoomActionUpdatePlan),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_showPlanUpdateSheet(context, cubit, l10n));
                    },
                  ),
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
                  ListTile(
                    leading: const Icon(Icons.vertical_align_top_outlined),
                    title: Text(l10n.coordinationPromoteSheetTitle),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        _showPromoteSheet(
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
                    leading: const Icon(Icons.help_outline),
                    title: Text(l10n.beaconRoomActionNeedInfo),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        _showNeedInfoSheet(
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
                    leading: const Icon(Icons.task_alt_outlined),
                    title: Text(l10n.beaconRoomActionMarkDone),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(
                        _showMarkDoneSheet(context, cubit, l10n, message),
                      );
                    },
                  ),
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
  ) async {
    final plan = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _BeaconRoomTextBottomSheet(
        title: l10n.beaconRoomActionUpdatePlan,
        hintText: l10n.beaconRoomStripPlanLabel,
        initialText: cubit.state.roomState?.currentPlan ?? '',
      ),
    );
    if (plan == null || !context.mounted) return;
    await cubit.updatePlan(plan);
  }

  Future<void> _showEditMessageSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final newBody = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kPaddingH.add(kPaddingSmallT),
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

  bool _roomCanSelfAsk(RoomCubit cubit) {
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

  bool _roomIsBeaconAuthor(RoomCubit cubit) {
    final myUserId = cubit.state.myUserId;
    for (final p in cubit.state.participants) {
      if (p.userId == myUserId && p.role == BeaconParticipantRoleBits.author) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showPromoteSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final canSelfAsk = _roomCanSelfAsk(cubit);
    final isAuthor = _roomIsBeaconAuthor(cubit);
    final askSeed = AskComposerSeed.fromMessage(
      messageId: message.id,
      messageBody: message.body,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kPaddingH.add(kPaddingSmallT),
              child: Text(
                l10n.coordinationPromoteSheetTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            if (canSelfAsk)
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(l10n.beaconRoomSelfAskFromMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    showBeaconRoomSelfAskSheet(
                      context,
                      beaconId: cubit.state.beaconId,
                      seed: askSeed,
                    ),
                  );
                },
              ),
            if (isAuthor)
              ListTile(
                leading: const Icon(Icons.drafts_outlined),
                title: Text(l10n.beaconPreparedAskFromMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    showPreparedAskEditorSheet(
                      context,
                      beaconId: cubit.state.beaconId,
                      seed: askSeed,
                      onSaved: () {},
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
                  _showMarkBlockerSheet(context, cubit, l10n, viewer, message),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(l10n.beaconRoomActionMarkAsk),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(
                  _showMarkAskSheet(context, cubit, l10n, viewer, message),
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
        ),
      ),
    );
  }

  List<BeaconParticipant> _admittedParticipantsForPromote(RoomCubit cubit) {
    final myUserId = cubit.state.myUserId;
    final myParticipantRole = cubit.state.participants
        .where((p) => p.userId == myUserId)
        .firstOrNull
        ?.role;
    final isAuthorOrSteward = myParticipantRole ==
            BeaconParticipantRoleBits.author ||
        myParticipantRole == BeaconParticipantRoleBits.steward;
    return isAuthorOrSteward
        ? cubit.state.participants
            .where((p) =>
                p.roomAccess == RoomAccessBits.admitted ||
                p.status == BeaconParticipantStatusBits.candidate ||
                p.status == BeaconParticipantStatusBits.offeredHelp)
            .toList()
        : cubit.state.participants
            .where((p) => p.roomAccess == RoomAccessBits.admitted)
            .toList();
  }

  Future<({String title, String body, String targetUserId})?>
      _showPromoteFieldsDialog({
    required BuildContext context,
    required L10n l10n,
    required Profile viewer,
    required RoomCubit cubit,
    required String dialogTitle,
    required String messageBody,
  }) async {
    final admitted = _admittedParticipantsForPromote(cubit);
    if (admitted.isEmpty) return null;

    final titleController = TextEditingController();
    final bodyController = TextEditingController(text: messageBody);
    var targetUserId = viewer.id;
    if (!admitted.any((p) => p.userId == targetUserId)) {
      targetUserId = admitted.first.userId;
    }

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return null;
      final body = bodyController.text.trim();
      if (body.isEmpty) return null;
      final titleRaw = titleController.text.trim();
      final title = titleRaw.isEmpty ? body : titleRaw;
      return (title: title, body: body, targetUserId: targetUserId);
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
    );
    if (fields == null || !context.mounted) return;
    await cubit.markAskFromMessage(
      messageId: message.id,
      title: fields.title,
      targetPersonId: fields.targetUserId,
      body: fields.body,
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
    );
    if (fields == null || !context.mounted) return;
    await cubit.markBlockerFromMessage(
      messageId: message.id,
      title: fields.title,
      body: fields.body,
      targetPersonId: fields.targetUserId,
    );
  }

  Future<void> _showNeedInfoSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final myUserId = cubit.state.myUserId;
    final myParticipantRole = cubit.state.participants
        .where((p) => p.userId == myUserId)
        .firstOrNull
        ?.role;
    final isAuthorOrSteward = myParticipantRole == BeaconParticipantRoleBits.author ||
        myParticipantRole == BeaconParticipantRoleBits.steward;
    final admitted = isAuthorOrSteward
        ? cubit.state.participants
            .where((p) =>
                p.roomAccess == RoomAccessBits.admitted ||
                p.status == BeaconParticipantStatusBits.candidate ||
                p.status == BeaconParticipantStatusBits.offeredHelp)
            .toList()
        : cubit.state.participants
            .where((p) => p.roomAccess == RoomAccessBits.admitted)
            .toList();
    if (admitted.isEmpty) return;
    final requestController = TextEditingController();
    var targetUserId = admitted.first.userId;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(l10n.beaconRoomActionNeedInfo),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          _needInfoTargetLabel(
                            l10n,
                            viewer,
                            p,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => targetUserId = v ?? targetUserId),
                ),
                TextField(
                  controller: requestController,
                  decoration: InputDecoration(
                    hintText: l10n.beaconRoomNeedInfoRequestHint,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
              ),
            ],
          ),
        ),
      );
      if (ok == true && context.mounted) {
        final note = requestController.text.trim();
        if (note.isEmpty) return;
        await cubit.needInfoFromMessage(
          messageId: message.id,
          targetUserId: targetUserId,
          requestText: note,
        );
      }
    } finally {
      requestController.dispose();
    }
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

  Future<void> _showMarkDoneSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final rs = cubit.state.roomState;
    final hasBlocker =
        rs?.openBlockerId != null && rs!.openBlockerId!.isNotEmpty;
    final myUserId = cubit.state.myUserId;
    final myParticipant = cubit.state.participants
        .where((p) => p.userId == myUserId)
        .firstOrNull;
    final ownNextMove = myParticipant?.nextMoveText?.trim() ?? '';
    final hasOwnNextMove = ownNextMove.isNotEmpty;

    // Selection: 0=messageOnly, 1=resolveBlocker, 2=myNextStep
    var selection = hasBlocker ? 1 : 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.beaconRoomMarkDoneTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasOwnNextMove)
                ListTile(
                  title: Text(l10n.beaconRoomMarkDoneMyNextStep(ownNextMove)),
                  leading: Icon(
                    selection == 2
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => setState(() => selection = 2),
                ),
              ListTile(
                title: Text(
                  hasBlocker &&
                          (rs.openBlockerTitle ?? '').trim().isNotEmpty
                      ? l10n.beaconRoomMarkDoneConfirmSingleBlocker(
                          rs.openBlockerTitle!.trim(),
                        )
                      : l10n.beaconRoomMarkDoneResolveBlocker,
                ),
                leading: Icon(
                  selection == 1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: message.linkedBlockerId == null && !hasBlocker
                    ? null
                    : () => setState(() => selection = 1),
              ),
              ListTile(
                title: Text(l10n.beaconRoomMarkDoneMessageOnly),
                leading: Icon(
                  selection == 0
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => setState(() => selection = 0),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      if (selection == 2 && hasOwnNextMove) {
        await cubit.participantSetNextMove(
          targetUserId: myUserId,
          nextMoveText: ownNextMove,
          nextMoveStatus: BeaconNextMoveStatusBits.done,
        );
      } else {
        await cubit.markMessageDone(
          messageId: message.id,
          resolveBlocker: selection == 1,
        );
      }
    }
  }

}

class _BeaconRoomTextBottomSheet extends StatefulWidget {
  const _BeaconRoomTextBottomSheet({
    required this.title,
    required this.hintText,
    this.initialText = '',
  });

  final String title;
  final String hintText;
  final String initialText;

  @override
  State<_BeaconRoomTextBottomSheet> createState() =>
      _BeaconRoomTextBottomSheetState();
}

class _BeaconRoomTextBottomSheetState extends State<_BeaconRoomTextBottomSheet> {
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingSmall,
        right: kSpacingSmall,
        top: kSpacingMedium,
        bottom: bottom + kSpacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              hintText: widget.hintText,
            ),
          ),
          const SizedBox(height: kSpacingMedium),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _PollCreateSheet extends StatefulWidget {
  const _PollCreateSheet({required this.cubit});
  final RoomCubit cubit;

  @override
  State<_PollCreateSheet> createState() => _PollCreateSheetState();
}

class _PollCreateSheetState extends State<_PollCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  String _question = '';
  final List<String> _variants = ['', ''];
  String _pollType = 'single';
  bool _isAnonymous = true;
  bool _allowRevote = true;
  bool _sending = false;

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final q = _question.trim();
    final vs = _variants
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (q.isEmpty || vs.length < 2) return;

    setState(() => _sending = true);
    try {
      await widget.cubit.createPoll(
        question: q,
        variants: vs,
        pollType: _pollType,
        isAnonymous: _isAnonymous,
        allowRevote: _allowRevote,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        showSnackBar(context, isError: true, text: e.toString());
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingMedium,
        right: kSpacingMedium,
        top: kSpacingMedium,
        bottom: MediaQuery.of(context).viewInsets.bottom + kSpacingMedium,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconRoomCreatePoll,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingMedium),
              PollingQuestionInput(
                onChanged: (v) => _question = v,
              ),
              const SizedBox(height: kSpacingSmall),
              ..._variants.asMap().entries.map(
                (entry) {
                  final idx = entry.key;
                  return Padding(
                    key: ValueKey(idx),
                    padding: const EdgeInsets.only(bottom: kSpacingSmall),
                    child: PollingVariantInput(
                      onChanged: (v) => _variants[idx] = v,
                      onRemove: _variants.length > 2
                          ? () => setState(() => _variants.removeAt(idx))
                          : () {},
                    ),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addOptionButton),
                onPressed: _variants.length < 10
                    ? () => setState(() => _variants.add(''))
                    : null,
              ),
              const SizedBox(height: kSpacingMedium),

              // Poll type selector
              Align(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('Single')),
                    ButtonSegment(value: 'multiple', label: Text('Multiple')),
                    ButtonSegment(value: 'range', label: Text('Range 1–5')),
                  ],
                  selected: {_pollType},
                  onSelectionChanged: (s) =>
                      setState(() => _pollType = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: kSpacingSmall),

              // Anonymous / open toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Anonymous'),
                subtitle: const Text('Hide who voted for what'),
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
              ),

              // Allow revote toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow changing answer'),
                value: _allowRevote,
                onChanged: (v) => setState(() => _allowRevote = v),
              ),

              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(l10n.beaconRoomSendPollButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedPlanCard extends StatelessWidget {
  const _PinnedPlanCard({required this.plan});

  final String plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final accent = theme.colorScheme.primary;
    return ExpansionTile(
      initiallyExpanded: false,
      leading: Container(width: 3, color: accent),
      title: Text(
        plan,
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.beaconRoomStripPlanLabel,
        style: theme.textTheme.labelSmall?.copyWith(color: accent),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(plan, style: theme.textTheme.bodySmall),
          ),
        ),
      ],
    );
  }
}
