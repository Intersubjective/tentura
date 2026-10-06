import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_threads/ui/util/room_reply_excerpt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/mention_suggestions_overlay.dart';
import 'package:tentura/features/beacon_threads/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/beacon_threads/ui/widget/participants_matching_mention_query.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_date_separator.dart';
import 'package:tentura/features/emoji/domain/emoji_catalog.dart';
import 'package:tentura/features/emoji/ui/widget/emoji_picker_button.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_pinned_fact_visibility_mark.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_unread_divider.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// True when [message] is a `childCreated` notice whose promotion source is
/// already in [loadedMessageIds] — the source bubble owns the preview card.
bool isRedundantChildCreatedNotice(
  RoomMessage message,
  Set<String> loadedMessageIds,
) {
  final payload = message.hierarchyPayload;
  if (payload is! RoomMessageHierarchyChildCreated) return false;
  final sourceMessageId = payload.sourceMessageId;
  return sourceMessageId != null && loadedMessageIds.contains(sourceMessageId);
}

/// Shared chat surface: scroll + message list + composer. Cubit-agnostic;
/// callers supply data and callbacks.
class BasicChatBody extends StatefulWidget {
  const BasicChatBody({
    required this.messages,
    required this.myProfile,
    required this.participants,
    required this.isLoading,
    this.onSend,
    this.onSendWithMentions,
    this.hasError = false,
    this.errorText = '',
    this.firstUnreadIndex = -1,
    this.firstUnreadMessageId,
    this.unreadCount = 0,
    this.onMarkSeenNearBottom,
    this.onMessageActions,
    this.onReply,
    this.onJumpToReply,
    this.replyTarget,
    this.onCancelReply,
    this.onPickFact,
    this.pendingQuotedFact,
    this.onCancelQuotedFact,
    this.composerPrefill,
    this.composerPrefillSeq = 0,
    this.onComposerPrefillApplied,
    this.onToggleReaction,
    this.onOpenFileAttachment,
    this.onVotePoll,
    this.onBatonRespond,
    this.onBatonSelect,
    this.onBatonCancel,
    this.header,
    this.emptyPlaceholder,
    this.imageRepository,
    this.clipboardImageRepository,
    this.enableComposerAttachments = true,
    this.enableParticipantMentions = true,
    this.composerReadOnlyHint,
    this.composerSendEnabled = true,
    this.onComposerContentChanged,
    this.jumpFabHeroTag = 'basic_chat_jump_latest',
    this.onScrollToPromoteSource,
    this.onOpenCoordinationItem,
    this.hideCoordinationLifecycleFooter = false,
    this.pinnedFactForMessage,
    this.pendingJumpMessageId,
    this.receiptIndex,
    this.capabilities = const RoomCapabilities.request(),
    this.hideUntilViewportPositioned = false,
    super.key,
  });

  final List<RoomMessage> messages;

  final Profile myProfile;

  final List<BeaconParticipant> participants;

  final bool isLoading;

  final bool hasError;

  final String errorText;

  /// Logical unread-list position (see `RoomState.firstUnreadIndex`); retained for
  /// callers that still key off an index. Divider placement uses
  /// [firstUnreadMessageId], not this value.
  final int firstUnreadIndex;

  /// When set with [unreadCount] > 0, the unread divider is rendered immediately
  /// before this message id in the physical [messages] list (pins may precede it).
  final String? firstUnreadMessageId;

  final int unreadCount;

  final Future<void> Function()? onMarkSeenNearBottom;

  final void Function(RoomMessage message)? onMessageActions;

  final void Function(RoomMessage message)? onReply;

  final void Function(String messageId)? onJumpToReply;

  final RoomMessage? replyTarget;

  final VoidCallback? onCancelReply;

  /// Invoked when the composer's attach-menu "Fact" item is tapped; hidden
  /// from the menu when null.
  final VoidCallback? onPickFact;

  /// Fact quoted into the composer, pending send.
  final BeaconFactCard? pendingQuotedFact;

  final VoidCallback? onCancelQuotedFact;

  /// Text another surface asked to put into the composer; applied once per
  /// [composerPrefillSeq], then [onComposerPrefillApplied] is called.
  final String? composerPrefill;

  final int composerPrefillSeq;

  final VoidCallback? onComposerPrefillApplied;

  final Future<void> Function(String messageId, String emoji)? onToggleReaction;

  final Future<void> Function(RoomMessageAttachment attachment)?
  onOpenFileAttachment;

  final Future<void> Function(
    String messageId,
    String pollingId,
    List<String> variantIds, {
    int? score,
  })?
  onVotePoll;

  final void Function(String messageId, String batonId, bool canHelp)?
  onBatonRespond;

  final void Function(String messageId, String batonId, String? userId)?
  onBatonSelect;

  final void Function(String messageId, String batonId)? onBatonCancel;

  final Future<bool> Function(String body, List<RoomPendingUpload> uploads)?
  onSend;

  final Future<bool> Function(
    String body,
    List<RoomPendingUpload> uploads,
    List<CommittedMention> mentions,
  )?
  onSendWithMentions;

  final Widget? header;

  final Widget? emptyPlaceholder;

  final ImageRepository? imageRepository;

  final ClipboardImageRepository? clipboardImageRepository;

  final bool enableComposerAttachments;

  final bool enableParticipantMentions;

  /// When non-null, the composer is visible but disabled and shows this hint.
  final String? composerReadOnlyHint;

  /// Host gate on top of the composer's own rules: false disables Send.
  final bool composerSendEnabled;

  /// Reports whether the composer holds text or an attachment, on change.
  final ValueChanged<bool>? onComposerContentChanged;

  /// Distinct [FloatingActionButton.small] hero tag when multiple chat bodies
  /// might exist in the same navigator context.
  final String jumpFabHeroTag;

  /// Telegram-style promote pin row → scrolls to the linked source message.
  final void Function(String messageId)? onScrollToPromoteSource;

  final void Function(CoordinationItem item)? onOpenCoordinationItem;

  final bool hideCoordinationLifecycleFooter;

  /// Active pinned fact originating from a message, if any.
  final BeaconFactCard? Function(RoomMessage message)? pinnedFactForMessage;

  /// When non-null, suppresses pruning of that message's [GlobalKey] during
  /// an in-flight jump scroll.
  final String? pendingJumpMessageId;

  /// Per-emission sender receipt lookup for own messages (discussion read watermarks).
  final RoomReceiptIndex? receiptIndex;

  /// Request-only features passed down to each [RoomMessageTile].
  final RoomCapabilities capabilities;

  /// Keeps the message list invisible until [BasicChatBodyState.
  /// onRoomDataChangedForViewport] has placed it (first unread or bottom), so
  /// the top of the history never flashes before the jump.
  final bool hideUntilViewportPositioned;

  @override
  State<BasicChatBody> createState() => BasicChatBodyState();
}

class BasicChatBodyState extends State<BasicChatBody> {
  final Map<String, GlobalKey> _messageKeys = {};
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String?> _highlightedMessageId = ValueNotifier<String?>(
    null,
  );

  static const _highlightDuration = Duration(milliseconds: 1200);

  Timer? _highlightTimer;

  bool _showJumpFab = false;
  bool _viewportScrollDone = false;

  /// Exposed for tests verifying per-tile highlight without list [setState].
  ValueListenable<String?> get highlightedMessageId => _highlightedMessageId;

  @visibleForTesting
  bool debugHasMessageKey(String id) => _messageKeys.containsKey(id);

  final GlobalKey<_BeaconRoomComposerState> _composerKey =
      GlobalKey<_BeaconRoomComposerState>();

  /// Last [KeyEventResult] returned for Escape while the composer is focused.
  @visibleForTesting
  KeyEventResult? get debugLastComposerEscapeKeyResult =>
      _composerKey.currentState?.debugLastComposerEscapeKeyResult;

  GlobalKey _messageKey(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  bool get isViewportScrollDone => _viewportScrollDone;

  bool get _listHidden =>
      widget.hideUntilViewportPositioned && !_viewportScrollDone;

  /// Initial viewport scroll: first unread or bottom. Used by beacon room.
  void onRoomDataChangedForViewport({
    required String? firstUnreadMessageId,
    required bool messagesEmpty,
  }) {
    if (_viewportScrollDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _viewportScrollAttempt(firstUnreadMessageId, messagesEmpty, 0);
    });
  }

  static const int _kScrollToMessageMaxPasses = 48;

  /// Scrolls so the row with the given message id is on screen. Off-screen rows may not be
  /// built yet, so we jump `ScrollController` to an estimated offset and
  /// retry across frames (same idea as `_viewportScrollAttempt`).
  /// Returns keyboard focus to the discussion composer (e.g. after an edit
  /// sheet closes) so the user can keep typing without clicking.
  void focusComposer() => _composerKey.currentState?.requestComposerFocus();

  Future<bool> scrollToMessage(String id) async {
    for (var pass = 0; pass < _kScrollToMessageMaxPasses; pass++) {
      if (!mounted) {
        return false;
      }
      final ctx = _messageKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.12,
        );
        _highlightTimer?.cancel();
        _highlightedMessageId.value = id;
        _highlightTimer = Timer(_highlightDuration, () {
          if (_highlightedMessageId.value == id) {
            _highlightedMessageId.value = null;
          }
        });
        return true;
      }

      final idx = widget.messages.indexWhere((m) => m.id == id);
      if (idx < 0) {
        return false;
      }

      if (!_scrollController.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }

      final pos = _scrollController.position;
      final n = widget.messages.length;
      final denom = n <= 1 ? 1.0 : (n - 1).toDouble();
      final targetPx = ((idx / denom) * pos.maxScrollExtent).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );

      if ((pos.pixels - targetPx).abs() > 6) {
        _scrollController.jumpTo(targetPx);
      } else {
        final up = (pos.pixels - pos.viewportDimension * 0.2).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if (up < pos.pixels - 1) {
          _scrollController.jumpTo(up);
        }
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  void _onMessageListScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final fromBottom = pos.maxScrollExtent - pos.pixels;
    final showJump = fromBottom > 56;
    if (showJump != _showJumpFab) {
      setState(() => _showJumpFab = showJump);
    }
    if (fromBottom <= 12) {
      final fn = widget.onMarkSeenNearBottom;
      if (fn != null) {
        unawaited(fn());
      }
    }
  }

  Future<void> _viewportScrollAttempt(
    String? firstUnreadMessageId,
    bool messagesEmpty,
    int pass,
  ) async {
    if (!mounted || _viewportScrollDone) return;

    if (firstUnreadMessageId != null) {
      final target = _messageKeys[firstUnreadMessageId]?.currentContext;
      if (target != null) {
        // Instant: the list may still be hidden, and an animated scroll from
        // the top reads as a flash of old history.
        await Scrollable.ensureVisible(target, alignment: 0.12);
        _onMessageListScroll();
        _markViewportScrollDone();
        return;
      }
      // Lazy list: the target row isn't built until we're near it.
      _jumpTowardsMessage(firstUnreadMessageId);
      if (pass < 24) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _viewportScrollAttempt(
            firstUnreadMessageId,
            messagesEmpty,
            pass + 1,
          );
        });
      } else {
        _markViewportScrollDone();
      }
      return;
    }

    if (messagesEmpty) {
      _markViewportScrollDone();
      return;
    }

    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      // Lazy-list extents are estimates: jumping builds the tail and moves
      // maxScrollExtent, so re-check next frame until the jump sticks.
      if ((pos.pixels - pos.maxScrollExtent).abs() >= 0.5 && pass < 24) {
        _scrollController.jumpTo(pos.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _viewportScrollAttempt(
            firstUnreadMessageId,
            messagesEmpty,
            pass + 1,
          );
        });
        return;
      }
      _onMessageListScroll();
      _markViewportScrollDone();
      await _invokeMarkSeenNearBottom();
      return;
    }

    if (pass < 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _viewportScrollAttempt(
          firstUnreadMessageId,
          messagesEmpty,
          pass + 1,
        );
      });
    } else {
      _markViewportScrollDone();
    }
  }

  void _markViewportScrollDone() {
    if (mounted && !_viewportScrollDone) {
      setState(() => _viewportScrollDone = true);
    }
  }

  /// Jumps to an index-proportional offset so a not-yet-built row gets laid
  /// out; [_viewportScrollAttempt] then finishes with `ensureVisible`.
  void _jumpTowardsMessage(String id) {
    if (!_scrollController.hasClients) return;
    final idx = widget.messages.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    final pos = _scrollController.position;
    final n = widget.messages.length;
    final denom = n <= 1 ? 1.0 : (n - 1).toDouble();
    final targetPx = ((idx / denom) * pos.maxScrollExtent).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((pos.pixels - targetPx).abs() > 6) {
      _scrollController.jumpTo(targetPx);
    }
  }

  Future<void> _invokeMarkSeenNearBottom() async {
    final fn = widget.onMarkSeenNearBottom;
    if (fn != null) {
      await fn();
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
    await _invokeMarkSeenNearBottom();
  }

  /// After the list grows (own send, or inbound while near bottom), pin to the
  /// new max extent once layout has applied. Jump — not animate — so we don't
  /// undershoot a maxScrollExtent that updates mid-animation.
  void _followLatestAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _onMessageListScroll();
      unawaited(_invokeMarkSeenNearBottom());
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onMessageListScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMessageListScroll());
  }

  @override
  void didUpdateWidget(covariant BasicChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currentIds = widget.messages.map((m) => m.id).toSet();
    final pending = widget.pendingJumpMessageId;
    _messageKeys.removeWhere(
      (id, _) => !currentIds.contains(id) && id != pending,
    );

    // Initial viewport (first unread / bottom) owns the first scroll; only
    // auto-follow after that so we don't fight unread targeting.
    if (!_viewportScrollDone) return;
    if (pending != null) return;
    final oldLen = oldWidget.messages.length;
    final newLen = widget.messages.length;
    if (newLen <= oldLen || newLen == 0) return;

    final newest = widget.messages.last;
    final mine = newest.authorId == widget.myProfile.id;
    final nearBottom =
        !_scrollController.hasClients ||
        (_scrollController.position.maxScrollExtent -
                _scrollController.position.pixels) <=
            56;
    if (!mine && !nearBottom) return;
    _followLatestAfterLayout();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _highlightedMessageId.dispose();
    _scrollController
      ..removeListener(_onMessageListScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final messages = widget.messages;
    final showListContent = !widget.hasError || messages.isNotEmpty;

    // The new hierarchy child-creation system never marks its own source
    // message (plan §3.4.9) — only the sibling `childCreated` notice row
    // carries `sourceMessageId`. Derive the reverse mapping once per build
    // so each tile can find its own promoted-child footer target, if any.
    final promotedChildBySourceMessageId = <String, String>{};
    final loadedMessageIds = <String>{};
    for (final m in messages) {
      loadedMessageIds.add(m.id);
      final payload = m.hierarchyPayload;
      if (payload is RoomMessageHierarchyChildCreated) {
        final sourceMessageId = payload.sourceMessageId;
        if (sourceMessageId != null) {
          promotedChildBySourceMessageId[sourceMessageId] =
              payload.childBeaconId;
        }
      }
    }

    // When the promotion source is in this loaded page, the source bubble
    // already carries the preview footer — hide the sibling notice card so
    // we never show two full cards for one publication. Keep building the
    // reverse map from the full list so pagination / source-missing stays
    // correct when the notice is the only row present.
    final visibleMessages = [
      for (final m in messages)
        if (!isRedundantChildCreatedNotice(m, loadedMessageIds)) m,
    ];

    // If the unread band targeted a skipped notice, attach it to the next
    // visible row so we do not drop the band entirely.
    var unreadBandMessageId = widget.firstUnreadMessageId;
    if (unreadBandMessageId != null) {
      final unreadIdx = messages.indexWhere((m) => m.id == unreadBandMessageId);
      if (unreadIdx >= 0 &&
          isRedundantChildCreatedNotice(
            messages[unreadIdx],
            loadedMessageIds,
          )) {
        unreadBandMessageId = null;
        for (var j = unreadIdx + 1; j < messages.length; j++) {
          if (!isRedundantChildCreatedNotice(
            messages[j],
            loadedMessageIds,
          )) {
            unreadBandMessageId = messages[j].id;
            break;
          }
        }
      }
    }

    return TenturaChatColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          Expanded(
            child: !showListContent
                ? Center(child: Text(widget.errorText))
                : widget.isLoading && messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator.adaptive(),
                  )
                : messages.isEmpty && widget.emptyPlaceholder != null
                ? widget.emptyPlaceholder!
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Laid out but unpainted until positioned, so row
                      // keys resolve for the unread jump.
                      Opacity(
                        opacity: _listHidden ? 0 : 1,
                        child: ListView.builder(
                          controller: _scrollController,
                          // Small gap so the last bubble (notably a full-width
                          // poll) doesn't sit flush against the composer, which
                          // made its tap target compete with the text field.
                          padding: const EdgeInsets.only(bottom: kSpacingSmall),
                          itemCount: visibleMessages.length,
                          itemBuilder: (context, i) {
                            final m = visibleMessages[i];
                            final prev = i == 0 ? null : visibleMessages[i - 1];
                            final next = i + 1 >= visibleMessages.length
                                ? null
                                : visibleMessages[i + 1];
                            final dateChanged =
                                prev == null ||
                                !roomMessageSameLocalDay(
                                  prev.createdAt,
                                  m.createdAt,
                                );
                            final unreads = widget.unreadCount;
                            final showUnreadBand =
                                unreads > 0 &&
                                unreadBandMessageId != null &&
                                m.id == unreadBandMessageId;

                            final toggle = widget.onToggleReaction;
                            final vote = widget.onVotePoll;
                            final pinnedFact = widget.pinnedFactForMessage
                                ?.call(
                                  m,
                                );
                            final messageTile = RoomMessageTile(
                              key: _messageKey(m.id),
                              message: m,
                              myProfile: widget.myProfile,
                              previousMessage: prev,
                              nextMessage: next,
                              promotedChildBeaconId:
                                  promotedChildBySourceMessageId[m.id],
                              breakGroupAbove:
                                  dateChanged ||
                                  showUnreadBand ||
                                  promotedChildBySourceMessageId.containsKey(
                                    prev.id,
                                  ),
                              onActionsPressed: widget.onMessageActions,
                              onReplyPressed: widget.onReply,
                              onJumpToReply: widget.onJumpToReply,
                              onToggleReaction: toggle,
                              onOpenFileAttachment: widget.onOpenFileAttachment,
                              participants: widget.participants,
                              onVotePoll: vote == null
                                  ? null
                                  : (pollingId, variantIds, {score}) => vote(
                                      m.id,
                                      pollingId,
                                      variantIds,
                                      score: score,
                                    ),
                              onBatonRespond: widget.onBatonRespond == null
                                  ? null
                                  : (batonId, canHelp) =>
                                        widget.onBatonRespond!(
                                          m.id,
                                          batonId,
                                          canHelp,
                                        ),
                              onBatonSelect: widget.onBatonSelect == null
                                  ? null
                                  : (batonId, userId) => widget.onBatonSelect!(
                                      m.id,
                                      batonId,
                                      userId,
                                    ),
                              onBatonCancel: widget.onBatonCancel == null
                                  ? null
                                  : (batonId) =>
                                        widget.onBatonCancel!(m.id, batonId),
                              onScrollToPromoteSource:
                                  widget.onScrollToPromoteSource,
                              onOpenCoordinationItem:
                                  widget.onOpenCoordinationItem,
                              hideCoordinationLifecycleFooter:
                                  widget.hideCoordinationLifecycleFooter,
                              pinnedFact:
                                  pinnedFact != null &&
                                      roomPinnedFactIsVisible(pinnedFact)
                                  ? pinnedFact
                                  : null,
                              highlightedMessageId: _highlightedMessageId,
                              receipt: widget.receiptIndex?.receiptFor(m),
                              capabilities: widget.capabilities,
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (dateChanged)
                                  RoomDateSeparator(date: m.createdAt),
                                if (showUnreadBand)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: RoomUnreadDivider(
                                      unreadCount: unreads,
                                    ),
                                  ),
                                messageTile,
                              ],
                            );
                          },
                        ),
                      ),
                      if (_showJumpFab && !_listHidden)
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: Badge(
                            isLabelVisible: widget.unreadCount > 0,
                            label: Text('${widget.unreadCount}'),
                            child: FloatingActionButton.small(
                              heroTag: widget.jumpFabHeroTag,
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
          _buildComposerRow(context),
        ],
      ),
    );
  }

  Widget _buildComposerRow(BuildContext context) {
    final repo = widget.imageRepository;
    final clipboardRepo = widget.clipboardImageRepository;
    final onSend = widget.onSend;
    final canCompose = repo != null && clipboardRepo != null && onSend != null;
    final initialLoadInProgress = widget.isLoading && widget.messages.isEmpty;

    return SafeArea(
      child: Material(
        child: Padding(
          padding: kPaddingH.add(kPaddingSmallT).add(kPaddingV),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: canCompose
                    ? BeaconRoomComposer(
                        key: _composerKey,
                        imageRepository: repo,
                        clipboardImageRepository: clipboardRepo,
                        isSending: initialLoadInProgress,
                        onSend: onSend,
                        onSendWithMentions: widget.onSendWithMentions,
                        participants: widget.participants,
                        enableAttachments: widget.enableComposerAttachments,
                        enableParticipantMentions:
                            widget.enableParticipantMentions,
                        readOnlyHint: widget.composerReadOnlyHint,
                        sendEnabled: widget.composerSendEnabled,
                        onContentChanged: widget.onComposerContentChanged,
                        replyTarget: widget.replyTarget,
                        onCancelReply: widget.onCancelReply,
                        onPickFact: widget.onPickFact,
                        pendingQuotedFact: widget.pendingQuotedFact,
                        onCancelQuotedFact: widget.onCancelQuotedFact,
                        prefill: widget.composerPrefill,
                        prefillSeq: widget.composerPrefillSeq,
                        onPrefillApplied: widget.onComposerPrefillApplied,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Room composer: mentions, optional attachments, send.
class BeaconRoomComposer extends StatefulWidget {
  const BeaconRoomComposer({
    required this.imageRepository,
    required this.clipboardImageRepository,
    required this.isSending,
    required this.onSend,
    required this.participants,
    this.onSendWithMentions,
    this.enableAttachments = true,
    this.enableParticipantMentions = true,
    this.readOnlyHint,
    this.sendEnabled = true,
    this.onContentChanged,
    this.replyTarget,
    this.onCancelReply,
    this.onPickFact,
    this.pendingQuotedFact,
    this.onCancelQuotedFact,
    this.prefill,
    this.prefillSeq = 0,
    this.onPrefillApplied,
    super.key,
  });

  final ImageRepository imageRepository;

  final ClipboardImageRepository clipboardImageRepository;

  final bool isSending;

  final Future<bool> Function(String body, List<RoomPendingUpload> uploads)
  onSend;

  final Future<bool> Function(
    String body,
    List<RoomPendingUpload> uploads,
    List<CommittedMention> mentions,
  )?
  onSendWithMentions;

  final List<BeaconParticipant> participants;

  final bool enableAttachments;

  final bool enableParticipantMentions;

  /// Non-null ⇒ composer is locked; also used as the disabled field hint.
  final String? readOnlyHint;

  /// Host gate: false disables Send (and the Enter key) without locking the
  /// field.
  final bool sendEnabled;

  /// Called when the composer starts or stops holding text or an attachment.
  final ValueChanged<bool>? onContentChanged;

  final RoomMessage? replyTarget;

  final VoidCallback? onCancelReply;

  /// Invoked when the attach-menu "Fact" item is tapped; hidden from the
  /// menu when null.
  final VoidCallback? onPickFact;

  /// Fact quoted into the composer, pending send.
  final BeaconFactCard? pendingQuotedFact;

  final VoidCallback? onCancelQuotedFact;

  /// Text put into the field (replacing what it held), cursor at the end;
  /// applied once per [prefillSeq].
  final String? prefill;

  final int prefillSeq;

  /// Called after [prefill] went into the field.
  final VoidCallback? onPrefillApplied;

  @override
  State<BeaconRoomComposer> createState() => _BeaconRoomComposerState();
}

class _BeaconRoomComposerState extends State<BeaconRoomComposer> {
  static final _composerBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(TenturaRadii.searchBar),
    borderSide: BorderSide.none,
  );

  @visibleForTesting
  KeyEventResult? debugLastComposerEscapeKeyResult;

  KeyEventResult _recordComposerEscapeResult(KeyEventResult result) {
    debugLastComposerEscapeKeyResult = result;
    return result;
  }

  final _text = MentionTextController(
    emojiForShortcode: EmojiCatalog.emojiForShortcode,
  );
  late final FocusNode _composerFocus;
  final _composerAnchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  List<BeaconParticipant> _overlaySuggestions = const [];
  List<EmojiMatch> _emojiSuggestions = const [];
  var _overlaySelectedIndex = 0;
  var _overlaySyncScheduled = false;
  var _hasText = false;
  var _reportedContent = false;
  var _submitting = false;

  final List<RoomPendingUpload> _pending = [];

  @override
  void initState() {
    super.initState();
    _composerFocus = FocusNode(onKeyEvent: _handleComposerKeyEvent);
    _text.addListener(_onTextChanged);
    _composerFocus.addListener(_onComposerFocusChange);
    _maybeApplyPrefill();
  }

  int _appliedPrefillSeq = 0;

  void _maybeApplyPrefill() {
    final text = widget.prefill;
    if (text == null ||
        text.isEmpty ||
        widget.prefillSeq == _appliedPrefillSeq ||
        widget.readOnlyHint != null) {
      return;
    }
    _appliedPrefillSeq = widget.prefillSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _composerFocus.requestFocus();
      widget.onPrefillApplied?.call();
    });
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_suggestionCount > 0) {
        _removeOverlay();
        return _recordComposerEscapeResult(KeyEventResult.handled);
      }
      if (widget.replyTarget != null && widget.onCancelReply != null) {
        widget.onCancelReply!();
        return _recordComposerEscapeResult(KeyEventResult.handled);
      }
      return _recordComposerEscapeResult(KeyEventResult.ignored);
    }
    if (key == LogicalKeyboardKey.keyV && _isPasteShortcutPressed()) {
      final readOnly = widget.readOnlyHint != null;
      if (widget.enableAttachments &&
          !readOnly &&
          !widget.isSending &&
          !_submitting) {
        unawaited(_pasteImage(fromKeyboard: true));
      }
      // Let the text field's own paste run too, so text clipboards still work.
      return KeyEventResult.ignored;
    }
    if (_suggestionCount == 0) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveMentionHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveMentionHighlight(-1);
      return KeyEventResult.handled;
    }
    final isCommit =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab;
    if (!isCommit) {
      return KeyEventResult.ignored;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _acceptSelectedSuggestion();
    });
    return KeyEventResult.handled;
  }

  /// Cmd+V on Apple platforms, Ctrl+V elsewhere (no Shift/Alt).
  bool _isPasteShortcutPressed() {
    final keyboard = HardwareKeyboard.instance;
    final isApple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final primary = isApple
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final other = isApple ? keyboard.isControlPressed : keyboard.isMetaPressed;
    return primary &&
        !other &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed;
  }

  /// Rows in whichever suggestion list (`@` or `:`) is open; 0 when none.
  int get _suggestionCount => math.min(
    _emojiSuggestions.isNotEmpty
        ? _emojiSuggestions.length
        : _overlaySuggestions.length,
    kComposerSuggestionsMaxRows,
  );

  void _moveMentionHighlight(int delta) {
    if (_suggestionCount == 0) {
      return;
    }
    final max = _suggestionCount;
    final next = (_overlaySelectedIndex + delta).clamp(0, max - 1);
    if (next == _overlaySelectedIndex) {
      return;
    }
    _overlaySelectedIndex = next;
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _composerFocus.removeListener(_onComposerFocusChange);
    _overlaySyncScheduled = false;
    _removeOverlay();
    _composerFocus.unfocus();
    _text.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BeaconRoomComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participants != widget.participants ||
        oldWidget.enableParticipantMentions !=
            widget.enableParticipantMentions) {
      _scheduleOverlaySync();
    }
    // Picking a reply target (overflow menu, hover button) means the user is
    // about to type; put the caret in the field.
    final target = widget.replyTarget;
    if (target != null &&
        target.id != oldWidget.replyTarget?.id &&
        widget.readOnlyHint == null) {
      requestComposerFocus();
    }
    _maybeApplyPrefill();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final hasText = _text.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    _reportContent();
    _scheduleOverlaySync();
  }

  void _reportContent() {
    final hasContent = _text.text.trim().isNotEmpty || _pending.isNotEmpty;
    if (hasContent == _reportedContent) return;
    _reportedContent = hasContent;
    widget.onContentChanged?.call(hasContent);
  }

  void _scheduleOverlaySync() {
    if (_overlaySyncScheduled) return;
    _overlaySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlaySyncScheduled = false;
      if (!mounted) return;
      _syncMentionOverlay();
    });
  }

  void _syncMentionOverlay() {
    final emojiToken = _text.activeEmojiToken;
    if (emojiToken != null) {
      final matches = EmojiCatalog.search(
        emojiToken.query,
        limit: kComposerSuggestionsMaxRows,
      );
      if (matches.isEmpty) {
        _removeOverlay();
      } else {
        _showOverlay(emoji: matches);
      }
      return;
    }
    if (!widget.enableParticipantMentions) {
      _removeOverlay();
      return;
    }
    final query = _text.activeMentionQuery;
    if (query == null) {
      _removeOverlay();
      return;
    }
    final suggestions = participantsMatchingMentionQuery(
      participants: widget.participants,
      query: query,
    ).take(5).toList(growable: false);
    if (suggestions.isEmpty) {
      _removeOverlay();
      return;
    }
    _showOverlay(mentions: suggestions);
  }

  void _removeOverlay() {
    _overlaySuggestions = const [];
    _emojiSuggestions = const [];
    _overlaySelectedIndex = 0;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Rect? _composerAnchorRect() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayRender = overlay?.context.findRenderObject();
    final targetRender = _composerAnchorKey.currentContext?.findRenderObject();
    if (overlayRender is! RenderBox || targetRender is! RenderBox) {
      return null;
    }
    if (!overlayRender.attached || !targetRender.attached) {
      return null;
    }

    final topLeft = targetRender.localToGlobal(
      Offset.zero,
      ancestor: overlayRender,
    );
    return topLeft & targetRender.size;
  }

  bool _acceptMentionSuggestion(BeaconParticipant participant) {
    final inserted = participant.handle.isNotEmpty
        ? _text.insertMention(participant.handle.toLowerCase())
        : _text.insertLiteralMentionText(
            '@${participant.userTitle.trim()}',
            userId: participant.userId,
          );
    _removeOverlay();
    if (inserted) {
      if (!_composerFocus.hasFocus) {
        _composerFocus.requestFocus();
      }
    }
    return inserted;
  }

  bool _acceptEmojiSuggestion(EmojiMatch match) {
    final inserted = _text.insertEmoji(match.entry.emoji);
    _removeOverlay();
    if (inserted && !_composerFocus.hasFocus) {
      _composerFocus.requestFocus();
    }
    return inserted;
  }

  bool _acceptSelectedSuggestion() {
    final count = _suggestionCount;
    if (count == 0) {
      return false;
    }
    final index = _overlaySelectedIndex.clamp(0, count - 1);
    return _emojiSuggestions.isNotEmpty
        ? _acceptEmojiSuggestion(_emojiSuggestions[index])
        : _acceptMentionSuggestion(_overlaySuggestions[index]);
  }

  /// Opens (or refreshes) the suggestion list: [mentions] for `@`, [emoji]
  /// for `:`. Only one kind is non-empty at a time.
  void _showOverlay({
    List<BeaconParticipant> mentions = const [],
    List<EmojiMatch> emoji = const [],
  }) {
    final sameItems =
        mentions.length == _overlaySuggestions.length &&
        emoji.length == _emojiSuggestions.length &&
        [
          for (var i = 0; i < mentions.length; i++)
            mentions[i].userId == _overlaySuggestions[i].userId,
          for (var i = 0; i < emoji.length; i++)
            emoji[i].entry.emoji == _emojiSuggestions[i].entry.emoji,
        ].every((ok) => ok);
    _overlaySuggestions = mentions;
    _emojiSuggestions = emoji;
    final count = mentions.length + emoji.length;
    if (!sameItems) {
      _overlaySelectedIndex = 0;
    } else if (_overlaySelectedIndex >= count) {
      _overlaySelectedIndex = count - 1;
    }
    if (_overlayEntry != null) {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _overlayEntry?.markNeedsBuild();
        });
      } else {
        _overlayEntry!.markNeedsBuild();
      }
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (_) {
        final list = _overlaySuggestions;
        final emojiList = _emojiSuggestions;
        if (list.isEmpty && emojiList.isEmpty) return const SizedBox.shrink();
        final anchor = _composerAnchorRect();
        if (anchor == null) return const SizedBox.shrink();
        void highlight(int index) {
          _overlaySelectedIndex = index;
          _overlayEntry?.markNeedsBuild();
        }

        if (emojiList.isNotEmpty) {
          return EmojiSuggestionsOverlay(
            suggestions: emojiList,
            anchor: anchor,
            selectedIndex: _overlaySelectedIndex,
            onDismiss: _removeOverlay,
            onSelect: _acceptEmojiSuggestion,
            onHighlight: highlight,
          );
        }
        return MentionSuggestionsOverlay(
          suggestions: list,
          anchor: anchor,
          selectedIndex: _overlaySelectedIndex,
          onDismiss: _removeOverlay,
          onSelect: _acceptMentionSuggestion,
          onHighlight: (index) {
            _overlaySelectedIndex = index;
            _overlayEntry?.markNeedsBuild();
          },
        );
      },
    );
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overlayEntry == null) return;
      overlay.insert(_overlayEntry!);
    });
  }

  int get _remainingSlots => kMaxRoomMessageAttachments - _pending.length;

  void _removePending(int index) {
    setState(() => _pending.removeAt(index));
    _reportContent();
  }

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
    _reportContent();
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

  /// file_picker 12 dropped `PlatformFile.extension`; derive from `name`.
  String? _extensionFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return null;
    }
    return name.substring(dot + 1).trim();
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

  /// Reads an image from the clipboard into the pending attachments.
  ///
  /// [fromKeyboard] is Ctrl/Cmd+V in the composer: the text field pastes text
  /// in parallel, so stay silent unless the clipboard actually held an image.
  Future<void> _pasteImage({bool fromKeyboard = false}) async {
    if (!fromKeyboard && _remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final l10n = L10n.of(context)!;
    try {
      final result = await widget.clipboardImageRepository.readImage();
      if (!mounted) {
        return;
      }
      switch (result.outcome) {
        case ClipboardImageReadOutcome.found:
          _tryAdd(result.upload!);
        case ClipboardImageReadOutcome.notFound:
          if (!fromKeyboard) {
            _snack(l10n.beaconRoomAttachPasteImageNotFound);
          }
        case ClipboardImageReadOutcome.unsupported:
          if (!fromKeyboard) {
            _snack(l10n.beaconRoomAttachPasteImageUnsupported);
          }
      }
    } on Object catch (_) {
      if (!mounted || fromKeyboard) {
        return;
      }
      _snack(l10n.beaconRoomAttachPasteImageReadFailed);
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
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) {
      return;
    }
    for (final pf in files) {
      if (_remainingSlots <= 0) {
        break;
      }
      final bytes = await pf.readAsBytes();
      final ext = _extensionFromFileName(pf.name);
      var mime = ext != null && ext.isNotEmpty
          ? _mimeFromExtension(ext)
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
    if (widget.readOnlyHint != null || _submitting || !widget.sendEnabled) {
      return;
    }
    final body = _text.text;
    final uploads = List<RoomPendingUpload>.from(_pending);
    if (body.trim().isEmpty &&
        uploads.isEmpty &&
        widget.pendingQuotedFact == null) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final sent =
          await (widget.onSendWithMentions?.call(
                body,
                uploads,
                _text.committedMentions,
              ) ??
              widget.onSend(body, uploads));
      if (!mounted) {
        return;
      }
      if (!sent) {
        return;
      }
      _removeOverlay();
      _text.clear();
      setState(_pending.clear);
      _reportContent();
      // The field is disabled while sending, which drops its focus; restore
      // it once re-enabled so type → send → type works without a click.
      requestComposerFocus();
    } on Object catch (_) {
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Requests composer focus after the next frame, once the field is enabled
  /// again and any closing route has released focus.
  void requestComposerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _composerFocus.hasFocus) {
        return;
      }
      _composerFocus.requestFocus();
    });
  }

  /// Once the composer gains focus on native platforms, ensure the platform
  /// text input connection opens on the next frame (after layout). Poll voting
  /// controls must not keep primary focus after interaction; `ExcludeFocus` on
  /// `RoomPollCard` handles that, and this covers any remaining
  /// focus->connection timing gap (EditableText #126312).
  void _onComposerFocusChange() {
    if (kIsWeb || !_composerFocus.hasFocus) {
      return;
    }
    _scheduleComposerKeyboardRequest();
  }

  void _scheduleComposerKeyboardRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestComposerKeyboard();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestComposerKeyboard(),
      );
    });
  }

  void _requestComposerKeyboardFromTap() {
    if (!_composerFocus.hasFocus) {
      _composerFocus.requestFocus();
    }
    _requestComposerKeyboard();
    if (!kIsWeb) {
      _scheduleComposerKeyboardRequest();
    }
  }

  void _requestComposerKeyboard() {
    if (kIsWeb || !mounted || !_composerFocus.hasFocus) {
      return;
    }
    _composerEditableText()?.requestKeyboard();
  }

  /// Locates the [EditableTextState] rendered under [_composerFocus].
  EditableTextState? _composerEditableText() {
    final focusContext = _composerFocus.context;
    if (focusContext == null) {
      return null;
    }
    EditableTextState? editable;
    void walk(Element element) {
      if (editable != null) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(walk);
    }

    focusContext.visitChildElements(walk);
    return editable;
  }

  Widget _pasteImageButton(L10n l10n, ThemeData theme, bool busy) {
    final readOnly = widget.readOnlyHint != null;
    final enabled = !busy && !readOnly && _remainingSlots > 0;
    return Semantics(
      identifier: TestIds.roomMessagePaste,
      button: true,
      child: IconButton(
        key: const ValueKey('paste'),
        tooltip: l10n.beaconRoomAttachPasteImage,
        onPressed: enabled ? () => unawaited(_pasteImage()) : null,
        icon: Icon(
          Icons.content_paste_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _attachMenuButton(L10n l10n, ThemeData theme, bool busy) {
    final readOnly = widget.readOnlyHint != null;
    final onPickFact = widget.onPickFact;
    final hasSlots = _remainingSlots > 0;
    return PopupMenuButton<String>(
      key: const ValueKey('attach'),
      tooltip: l10n.beaconRoomAttachMenuTooltip,
      enabled: !busy && !readOnly,
      onSelected: (v) async {
        if (busy || readOnly) {
          return;
        }
        if (v == 'img') {
          await _pickImages();
        } else if (v == 'file') {
          await _pickFiles();
        } else if (v == 'fact') {
          onPickFact?.call();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'img',
          enabled: hasSlots,
          child: Text(l10n.beaconRoomAttachPickImages),
        ),
        PopupMenuItem(
          value: 'file',
          enabled: hasSlots,
          child: Text(l10n.beaconRoomAttachPickFiles),
        ),
        if (onPickFact != null)
          PopupMenuItem(
            value: 'fact',
            child: Text(l10n.beaconRoomAttachPickFact),
          ),
      ],
      icon: Icon(
        Icons.attach_file_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _attachSuffixActions(L10n l10n, ThemeData theme, bool busy) {
    return Row(
      key: const ValueKey('attach-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _pasteImageButton(l10n, theme, busy),
        _attachMenuButton(l10n, theme, busy),
      ],
    );
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
        onDeleted: busy ? null : () => _removePending(index),
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
              onPressed: () => _removePending(index),
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
    final readOnly = widget.readOnlyHint != null;
    final busy = widget.isSending || _submitting;
    final locked = busy || readOnly;
    final isCompact = context.windowClass == WindowClass.compact;
    final showAttach =
        widget.enableAttachments && !readOnly && !(isCompact && _hasText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyTarget != null)
          _ComposerReplyBanner(
            target: widget.replyTarget!,
            onCancelReply: widget.onCancelReply,
          ),
        if (widget.pendingQuotedFact != null)
          _ComposerQuotedFactBanner(
            fact: widget.pendingQuotedFact!,
            onCancelQuotedFact: widget.onCancelQuotedFact,
          ),
        if (widget.enableAttachments && !readOnly && _pending.isNotEmpty)
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
            Expanded(
              child: KeyedSubtree(
                key: _composerAnchorKey,
                child: Semantics(
                  identifier: TestIds.roomMessageInput,
                  textField: true,
                  child: TextField(
                    key: TestIds.key(TestIds.roomMessageInput),
                    controller: _text,
                    focusNode: _composerFocus,
                    // Filled, rounded composer (UI review #204) instead of
                    // the bare underline field.
                    decoration: InputDecoration(
                      hintText:
                          widget.readOnlyHint ?? l10n.beaconRoomMessageHint,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: context.tt.cardGap + context.tt.tightGap,
                        vertical: context.tt.cardGap,
                      ),
                      border: _composerBorder,
                      enabledBorder: _composerBorder,
                      disabledBorder: _composerBorder,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          TenturaRadii.searchBar,
                        ),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      prefixIcon: readOnly
                          ? null
                          : EmojiPickerButton(
                              controller: _text,
                              enabled: !locked,
                              onClosed: _requestComposerKeyboardFromTap,
                            ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 2 * kMinInteractiveDimension,
                        minHeight: kMinInteractiveDimension,
                      ),
                      suffixIcon: widget.enableAttachments && !readOnly
                          ? AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: showAttach
                                  ? _attachSuffixActions(l10n, theme, busy)
                                  : const SizedBox.shrink(
                                      key: ValueKey('attach-hidden'),
                                    ),
                            )
                          : null,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    enabled: !locked,
                    onTapAlwaysCalled: true,
                    onTap: _requestComposerKeyboardFromTap,
                    onSubmitted: (_) {
                      if (_acceptSelectedSuggestion()) {
                        return;
                      }
                      unawaited(_submit());
                    },
                    onTapOutside: (_) {
                      _removeOverlay();
                      // Only dismiss our own keyboard; don't yank focus from
                      // poll interactives (sliders/buttons) elsewhere on screen.
                      if (_composerFocus.hasFocus) {
                        _composerFocus.unfocus();
                      }
                    },
                  ),
                ),
              ),
            ),
            // Part of the field's tap region so tapping Send does not count
            // as a tap outside the composer (which would unfocus it).
            TextFieldTapRegion(
              child: Semantics(
                identifier: TestIds.roomMessageSend,
                button: true,
                child: IconButton(
                  key: TestIds.key(TestIds.roomMessageSend),
                  icon: const Icon(Icons.send_rounded),
                  tooltip: L10n.of(context)?.tooltipSendMessage,
                  onPressed: locked || !widget.sendEnabled
                      ? null
                      : () => unawaited(_submit()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ComposerReplyBanner extends StatelessWidget {
  const _ComposerReplyBanner({
    required this.target,
    this.onCancelReply,
  });

  final RoomMessage target;

  final VoidCallback? onCancelReply;

  static const _accentWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final authorName = target.author.shownName;
    final excerpt = roomReplyExcerptFor(
      excerpt: roomReplyExcerpt(target),
      hasAttachments: target.attachments.isNotEmpty,
      l10n: l10n,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpacingSmall),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(TenturaRadii.accentBar),
              ),
              child: const SizedBox(width: _accentWidth),
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.beaconRoomReplyingTo(authorName),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    excerpt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onCancelReply != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                onPressed: onCancelReply,
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerQuotedFactBanner extends StatelessWidget {
  const _ComposerQuotedFactBanner({
    required this.fact,
    this.onCancelQuotedFact,
  });

  final BeaconFactCard fact;

  final VoidCallback? onCancelQuotedFact;

  static const _accentWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;

    return Padding(
      key: const ValueKey('quoted-fact-banner'),
      padding: const EdgeInsets.only(bottom: kSpacingSmall),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.tertiary,
                borderRadius: BorderRadius.circular(TenturaRadii.accentBar),
              ),
              child: const SizedBox(width: _accentWidth),
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.beaconRoomQuotedFactFrom(fact.pinnedByTitle),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.tertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fact.attachments.any(
                    (a) => a.isImage && a.imageId.isNotEmpty,
                  )) ...[
                    SizedBox(height: tt.tightGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        TenturaRadii.cardDense,
                      ),
                      child: SizedBox(
                        width: tt.avatarSize,
                        height: tt.avatarSize,
                        child: roomAttachmentAlbumThumbnail(
                          context,
                          fact.attachments.firstWhere(
                            (a) => a.isImage && a.imageId.isNotEmpty,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (fact.factText.trim().isNotEmpty)
                    Text(
                      fact.factText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onCancelQuotedFact != null)
              IconButton(
                key: const ValueKey('quoted-fact-close'),
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                onPressed: onCancelQuotedFact,
              ),
          ],
        ),
      ),
    );
  }
}
