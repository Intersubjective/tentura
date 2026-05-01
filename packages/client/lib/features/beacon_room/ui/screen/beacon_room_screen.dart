import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/room_cubit.dart';
import '../widget/beacon_room_you_strip.dart';
import '../widget/fact_actions_sheet.dart';
import '../widget/room_facts_sheet.dart';
import '../widget/room_message_tile.dart';
import '../widget/room_now_strip.dart';
import '../widget/room_unread_divider.dart';

@RoutePage()
class BeaconRoomScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconRoomScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

  @override
  Widget wrappedRoute(_) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ScreenCubit()),
      BlocProvider(
        create: (_) => RoomCubit(beaconId: beaconId),
      ),
    ],
    child: MultiBlocListener(
      listeners: [
        const BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<RoomCubit, RoomState>(
          listenWhen: (p, c) => c.status != p.status,
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  State<BeaconRoomScreen> createState() => _BeaconRoomScreenState();
}

class _BeaconRoomScreenState extends State<BeaconRoomScreen> {
  final Map<String, GlobalKey> _messageKeys = {};
  final ScrollController _scrollController = ScrollController();

  bool _showJumpFab = false;
  bool _viewportScrollDone = false;

  GlobalKey _messageKey(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  void _onMessageListScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final cubit = context.read<RoomCubit>();
    final pos = _scrollController.position;
    final fromBottom = pos.maxScrollExtent - pos.pixels;
    final showJump = fromBottom > 56;
    if (showJump != _showJumpFab) {
      setState(() => _showJumpFab = showJump);
    }
    if (fromBottom <= 12) {
      unawaited(cubit.markSeenNowIfNeeded());
    }
  }

  void _viewportListener(BuildContext context, RoomCubit cubit) {
    if (_viewportScrollDone) return;
    if (cubit.state.status != const StateIsSuccess()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _viewportScrollAttempt(context, cubit, 0);
    });
  }

  Future<void> _viewportScrollAttempt(
    BuildContext context,
    RoomCubit cubit,
    int pass,
  ) async {
    if (!context.mounted || _viewportScrollDone) return;

    final s = cubit.state;
    final fid = s.firstUnreadMessageId;

    if (fid != null) {
      final target = _messageKeys[fid]?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.12,
        );
        _onMessageListScroll();
        if (context.mounted) {
          setState(() => _viewportScrollDone = true);
        }
        return;
      }
      if (pass < 24) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _viewportScrollAttempt(context, cubit, pass + 1);
        });
      }
      return;
    }

    if (s.messages.isEmpty) {
      setState(() => _viewportScrollDone = true);
      return;
    }

    final scrollPos =
        _scrollController.hasClients ? _scrollController.position : null;
    if (scrollPos != null && scrollPos.maxScrollExtent >= 0) {
      _scrollController.jumpTo(scrollPos.maxScrollExtent);
      _onMessageListScroll();
      setState(() => _viewportScrollDone = true);
      return;
    }

    if (pass < 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _viewportScrollAttempt(context, cubit, pass + 1);
      });
    }
  }

  Future<void> _jumpToLatest() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
    _onMessageListScroll();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onMessageListScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMessageListScroll());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onMessageListScroll)
      ..dispose();
    super.dispose();
  }

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
              final target = _messageKeys[id]?.currentContext;
              if (target != null) {
                await Scrollable.ensureVisible(
                  target,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  alignment: 0.12,
                );
              }
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
              );
            }
          },
        ),
        BlocListener<RoomCubit, RoomState>(
          listenWhen: (p, c) =>
              !_viewportScrollDone &&
              c.status == const StateIsSuccess() &&
              (p.messages != c.messages || p.status != c.status),
          listener: (ctx, s) {
            _viewportListener(ctx, ctx.read<RoomCubit>());
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
            p.nowCollapsed != c.nowCollapsed ||
            p.youCollapsed != c.youCollapsed ||
            p.unreadAnchorAt != c.unreadAnchorAt ||
            p.pendingMarkSeen != c.pendingMarkSeen ||
            p.status != c.status ||
            p.hasError != c.hasError,
        builder: (context, state) {
          final cubit = context.read<RoomCubit>();
          final err = state.status is StateHasError
              ? (state.status as StateHasError).error.toString()
              : '';
          BeaconParticipant? myRow;
          for (final pr in state.participants) {
            if (pr.userId == myProfile.id) {
              myRow = pr;
              break;
            }
          }

          return Scaffold(
            appBar: AppBar(
              leading: Builder(
                builder: (ctx) {
                  final router = ctx.router;
                  final canPop = router.canPop();
                  return IconButton(
                    icon: canPop
                        ? const Icon(Icons.arrow_back_rounded)
                        : const Icon(Icons.close_rounded),
                    onPressed: () {
                      if (canPop) {
                        unawaited(router.maybePop());
                      } else {
                        unawaited(router.navigatePath(kPathHome));
                      }
                    },
                  );
                },
              ),
              title: Text(l10n.beaconRoomTitle),
              actions: [
                IconButton(
                  tooltip: l10n.beaconRoomFactsBrowseTooltip,
                  icon: const Icon(Icons.manage_search_outlined),
                  onPressed: () => unawaited(
                    showRoomFactsSheet(
                      context,
                      cubit: cubit,
                      viewerUserId: myProfile.id,
                    ),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                if (state.roomState != null)
                  RoomNowStrip(
                    roomState: state.roomState!,
                    factCards: state.factCards,
                    collapsed: state.nowCollapsed,
                    onToggleCollapse: cubit.toggleNowCollapsed,
                    onOpenFact: (f) => showFactActionsSheet(
                      context,
                      cubit: cubit,
                      fact: f,
                    ),
                    onOpenFileAttachment: (a) => _openRoomFileAttachment(
                      context,
                      cubit,
                      l10n,
                      a,
                    ),
                  ),
                BeaconRoomYouStrip(
                  myParticipant: myRow,
                  collapsed: state.youCollapsed,
                  onToggleCollapse: cubit.toggleYouCollapsed,
                  onEditNextMove: () => unawaited(
                    _showNextMoveSheet(
                      context,
                      cubit,
                      l10n,
                      targetUserId: myProfile.id,
                    ),
                  ),
                ),
                Expanded(
                  child: state.hasError && state.messages.isEmpty
                      ? Center(child: Text(err))
                      : Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(bottom: 72),
                              itemCount: state.messages.length,
                              itemBuilder: (context, i) {
                                final m = state.messages[i];
                                final pf = cubit.factForRoomMessage(m);
                                final isCoord =
                                    _roomMessageIsCoordinationStateCard(m);
                                final idxUnread = state.firstUnreadIndex;
                                final unreads = state.unreadCount;
                                final showUnreadBand = unreads > 0 &&
                                    idxUnread >= 0 &&
                                    i == idxUnread;

                                final messageTile = RoomMessageTile(
                                  key: _messageKey(m.id),
                                  message: m,
                                  myProfile: myProfile,
                                  onPinnedFactManage: (!isCoord && pf != null)
                                      ? () => showFactActionsSheet(
                                            context,
                                            cubit: cubit,
                                            fact: pf,
                                          )
                                      : null,
                                  onActionsPressed: (msg) =>
                                      _onMessageActionsPressed(
                                        context,
                                        cubit,
                                        l10n,
                                        myProfile,
                                        msg,
                                      ),
                                  onToggleReaction: (messageId, emoji) =>
                                      cubit.toggleReaction(
                                        messageId: messageId,
                                        emoji: emoji,
                                      ),
                                  onOpenFileAttachment: (a) =>
                                      _openRoomFileAttachment(
                                        context,
                                        cubit,
                                        l10n,
                                        a,
                                      ),
                                );

                                if (!showUnreadBand) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 4),
                                    child: messageTile,
                                  );
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child:
                                          RoomUnreadDivider(unreadCount: unreads),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: messageTile,
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (_showJumpFab)
                              Positioned(
                                right: 12,
                                bottom: 8,
                                child: Badge(
                                  isLabelVisible: state.unreadCount > 0,
                                  label: Text('${state.unreadCount}'),
                                  child: FloatingActionButton.small(
                                    heroTag: 'beacon_room_jump_latest',
                                    tooltip: l10n.beaconRoomScrollToLatestTooltip,
                                    onPressed: () => unawaited(_jumpToLatest()),
                                    child: const Icon(
                                      Icons.arrow_downward_rounded,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (state.isLoading && state.messages.isEmpty)
                  const Padding(
                    padding: kPaddingV,
                    child: CircularProgressIndicator(),
                  ),
                SafeArea(
                  child: Material(
                    child: Padding(
                      padding: kPaddingH.add(kPaddingSmallT).add(kPaddingV),
                      child: BeaconRoomComposer(
                        imageRepository: GetIt.I<ImageRepository>(),
                        isSending: state.isLoading,
                        onSend: (body, uploads) => cubit.sendMessage(
                          body: body,
                          uploads: uploads,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

  void _onMessageActionsPressed(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) {
    final pf = cubit.factForRoomMessage(message);
    final showFactInMenu = !_roomMessageIsCoordinationStateCard(message);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return SafeArea(
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
                        _confirmUnpinFactFromMessage(context, cubit, l10n, pf),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(l10n.beaconRoomActionMarkBlocker),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(
                      _showMarkBlockerSheet(context, cubit, l10n, message),
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

  Future<void> _showPlanUpdateSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
  ) async {
    final controller = TextEditingController(
      text: cubit.state.roomState?.currentPlan ?? '',
    );
    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
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
                  l10n.beaconRoomActionUpdatePlan,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpacingSmall),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: l10n.beaconRoomStripPlanLabel,
                  ),
                ),
                const SizedBox(height: kSpacingMedium),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
                ),
              ],
            ),
          );
        },
      );
      if (ok == true && context.mounted) {
        final t = controller.text.trim();
        await cubit.updatePlan(t);
      }
    } finally {
      controller.dispose();
    }
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

  Future<void> _showMarkBlockerSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) async {
    final controller = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.beaconRoomActionMarkBlocker),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: l10n.beaconRoomBlockerTitleHint,
            ),
            autofocus: true,
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
      );
      if (ok == true && context.mounted) {
        final t = controller.text.trim();
        if (t.isEmpty) return;
        await cubit.markBlockerFromMessage(messageId: message.id, title: t);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showNeedInfoSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    Profile viewer,
    RoomMessage message,
  ) async {
    final admitted = cubit.state.participants
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
    final onlyBlocker =
        rs?.openBlockerId != null && rs!.openBlockerId!.isNotEmpty;
    var resolveBlocker = onlyBlocker;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.beaconRoomMarkDoneTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.beaconRoomMarkDoneMessageOnly),
                leading: Icon(
                  resolveBlocker
                      ? Icons.radio_button_off
                      : Icons.radio_button_checked,
                ),
                onTap: () => setState(() => resolveBlocker = false),
              ),
              ListTile(
                title: Text(
                  onlyBlocker && (rs.openBlockerTitle ?? '').trim().isNotEmpty
                      ? l10n.beaconRoomMarkDoneConfirmSingleBlocker(
                          rs.openBlockerTitle!.trim(),
                        )
                      : l10n.beaconRoomMarkDoneResolveBlocker,
                ),
                leading: Icon(
                  resolveBlocker
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: message.linkedBlockerId == null && !onlyBlocker
                    ? null
                    : () => setState(() => resolveBlocker = true),
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
      await cubit.markMessageDone(
        messageId: message.id,
        resolveBlocker: resolveBlocker,
      );
    }
  }

  Future<void> _openRoomFileAttachment(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessageAttachment attachment,
  ) async {
    try {
      final bytes = await cubit.downloadRoomAttachment(attachment.id);
      final name = attachment.fileName.trim().isEmpty
          ? 'file'
          : attachment.fileName.trim();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: name,
              mimeType: attachment.mime,
            ),
          ],
        ),
      );
    } on Object catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.beaconRoomAttachmentOpenFailed)),
        );
      }
    }
  }

  Future<void> _showNextMoveSheet(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n, {
    required String targetUserId,
  }) async {
    final controller = TextEditingController();
    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
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
                  l10n.beaconRoomYouStripEditNextMove,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpacingSmall),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: l10n.beaconRoomYouStripNextMoveLabel,
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: kSpacingMedium),
                FilledButton(
                  onPressed: () {
                    final t = controller.text.trim();
                    if (t.isEmpty) return;
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
                ),
              ],
            ),
          );
        },
      );
      if (ok != true || !context.mounted) return;
      final text = controller.text.trim();
      if (text.isEmpty) return;
      await cubit.participantSetNextMove(
        targetUserId: targetUserId,
        nextMoveText: text,
      );
    } finally {
      controller.dispose();
    }
  }
}

class BeaconRoomComposer extends StatefulWidget {
  const BeaconRoomComposer({
    required this.imageRepository,
    required this.isSending,
    required this.onSend,
    super.key,
  });

  final ImageRepository imageRepository;

  final bool isSending;

  final Future<void> Function(String body, List<RoomPendingUpload> uploads)
  onSend;

  @override
  State<BeaconRoomComposer> createState() => _BeaconRoomComposerState();
}

class _BeaconRoomComposerState extends State<BeaconRoomComposer> {
  final _text = TextEditingController();

  final List<RoomPendingUpload> _pending = [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _remainingSlots => kMaxRoomMessageAttachments - _pending.length;

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _withinSize(Uint8List bytes) {
    if (bytes.length <= kMaxRoomMessageAttachmentBytes) {
      return true;
    }
    const mb = kMaxRoomMessageAttachmentBytes ~/ (1024 * 1024);
    _snack(L10n.of(context)!.beaconRoomAttachmentTooLarge(mb));
    return false;
  }

  void _tryAdd(RoomPendingUpload upload) {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    if (!_withinSize(upload.bytes)) {
      return;
    }
    setState(() => _pending.add(upload));
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickImages() async {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final picks = await widget.imageRepository.pickMultipleImages();
    if (!mounted || picks.isEmpty) {
      return;
    }
    for (final p in picks) {
      if (_remainingSlots <= 0) {
        break;
      }
      _tryAdd(
        RoomPendingUpload(
          bytes: p.bytes,
          fileName: p.fileName,
          mimeType: 'image/jpeg',
        ),
      );
    }
  }

  Future<void> _pickFiles() async {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    for (final pf in result.files) {
      if (_remainingSlots <= 0) {
        break;
      }
      final bytes = pf.bytes;
      if (bytes == null) {
        continue;
      }
      var mime = pf.extension != null && pf.extension!.trim().isNotEmpty
          ? _mimeFromExtension(pf.extension!)
          : 'application/octet-stream';
      final sniffed = inferImageMimeFromLeadingBytes(bytes);
      if (sniffed != null) {
        mime = sniffed;
      }
      _tryAdd(
        RoomPendingUpload(
          bytes: bytes,
          fileName: pf.name,
          mimeType: mime,
        ),
      );
    }
  }

  Future<void> _submit() async {
    final body = _text.text;
    final uploads = List<RoomPendingUpload>.from(_pending);
    if (body.trim().isEmpty && uploads.isEmpty) {
      return;
    }
    try {
      await widget.onSend(body, uploads);
      if (!mounted) {
        return;
      }
      _text.clear();
      setState(_pending.clear);
    } on Object catch (_) {}
  }

  Widget _pendingAttachmentPreview(
    BuildContext context,
    ThemeData theme,
    bool busy,
    int index,
  ) {
    final loc = MaterialLocalizations.of(context);
    final u = _pending[index];
    final isImage = u.mimeType.toLowerCase().startsWith('image/');
    if (!isImage) {
      return InputChip(
        label: Text(
          u.fileName.trim().isEmpty
              ? L10n.of(context)!.beaconRoomAttachmentUntitled
              : u.fileName,
          style: theme.textTheme.labelMedium,
          overflow: TextOverflow.ellipsis,
        ),
        onDeleted: busy ? null : () => setState(() => _pending.removeAt(index)),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Image.memory(
              u.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        if (!busy)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.92,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: loc.deleteButtonTooltip,
              iconSize: 20,
              onPressed: () => setState(() => _pending.removeAt(index)),
              icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final busy = widget.isSending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpacingSmall),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _pending.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: kSpacingSmall),
                      child: _pendingAttachmentPreview(
                        context,
                        theme,
                        busy,
                        i,
                      ),
                    ),
                ],
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PopupMenuButton<String>(
              tooltip: l10n.beaconRoomAttachMenuTooltip,
              enabled: !busy && _remainingSlots > 0,
              onSelected: (v) async {
                if (busy) {
                  return;
                }
                if (v == 'img') {
                  await _pickImages();
                } else if (v == 'file') {
                  await _pickFiles();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'img',
                  child: Text(l10n.beaconRoomAttachPickImages),
                ),
                PopupMenuItem(
                  value: 'file',
                  child: Text(l10n.beaconRoomAttachPickFiles),
                ),
              ],
              icon: const Icon(Icons.attach_file_rounded),
            ),
            Expanded(
              child: TextField(
                controller: _text,
                decoration: InputDecoration(
                  hintText: l10n.beaconRoomMessageHint,
                ),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                enabled: !busy,
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded),
              onPressed: busy ? null : () => unawaited(_submit()),
            ),
          ],
        ),
      ],
    );
  }
}
