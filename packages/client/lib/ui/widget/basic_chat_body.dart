import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/mention_suggestions_overlay.dart';
import 'package:tentura/features/beacon_room/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_date_separator.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_unread_divider.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Shared chat surface: scroll + message list + composer. Cubit-agnostic;
/// callers supply data and callbacks.
class BasicChatBody extends StatefulWidget {
  const BasicChatBody({
    required this.messages,
    required this.myProfile,
    required this.participants,
    required this.isLoading,
    this.onSend,
    this.hasError = false,
    this.errorText = '',
    this.firstUnreadIndex = -1,
    this.unreadCount = 0,
    this.onMarkSeenNearBottom,
    this.onMessageActions,
    this.onToggleReaction,
    this.onOpenFileAttachment,
    this.onVotePoll,
    this.header,
    this.emptyPlaceholder,
    this.imageRepository,
    this.enableComposerAttachments = true,
    this.enableParticipantMentions = true,
    this.jumpFabHeroTag = 'basic_chat_jump_latest',
    this.onScrollToPromoteSource,
    this.onOpenCoordinationItem,
    this.hideCoordinationLifecycleFooter = false,
    super.key,
  });

  final List<RoomMessage> messages;

  final Profile myProfile;

  final List<BeaconParticipant> participants;

  final bool isLoading;

  final bool hasError;

  final String errorText;

  /// Same semantics as [RoomState.firstUnreadIndex].
  final int firstUnreadIndex;

  final int unreadCount;

  final Future<void> Function()? onMarkSeenNearBottom;

  final void Function(RoomMessage message)? onMessageActions;

  final Future<void> Function(String messageId, String emoji)? onToggleReaction;

  final Future<void> Function(RoomMessageAttachment attachment)?
      onOpenFileAttachment;

  final Future<void> Function(
    String messageId,
    String pollingId,
    List<String> variantIds, {
    int? score,
  })? onVotePoll;

  final Future<void> Function(String body, List<RoomPendingUpload> uploads)?
      onSend;

  final Widget? header;

  final Widget? emptyPlaceholder;

  final ImageRepository? imageRepository;

  final bool enableComposerAttachments;

  final bool enableParticipantMentions;

  /// Distinct [FloatingActionButton.small] hero tag when multiple chat bodies
  /// might exist in the same navigator context.
  final String jumpFabHeroTag;

  /// Telegram-style promote pin row → scrolls to the linked source message.
  final void Function(String messageId)? onScrollToPromoteSource;

  final void Function(CoordinationItem item)? onOpenCoordinationItem;

  final bool hideCoordinationLifecycleFooter;

  @override
  State<BasicChatBody> createState() => BasicChatBodyState();
}

class BasicChatBodyState extends State<BasicChatBody> {
  final Map<String, GlobalKey> _messageKeys = {};
  final ScrollController _scrollController = ScrollController();

  bool _showJumpFab = false;
  bool _viewportScrollDone = false;

  GlobalKey _messageKey(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  bool get isViewportScrollDone => _viewportScrollDone;

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

  /// Scrolls so the row with [id] is on screen. Off-screen rows may not be
  /// built yet, so we jump `ScrollController` to an estimated offset and
  /// retry across frames (same idea as [_viewportScrollAttempt]).
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
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.12,
        );
        _onMessageListScroll();
        if (mounted) {
          setState(() => _viewportScrollDone = true);
        }
        return;
      }
      if (pass < 24) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _viewportScrollAttempt(firstUnreadMessageId, messagesEmpty, pass + 1);
        });
      }
      return;
    }

    if (messagesEmpty) {
      if (mounted) {
        setState(() => _viewportScrollDone = true);
      }
      return;
    }

    final scrollPos = _scrollController.hasClients
        ? _scrollController.position
        : null;
    if (scrollPos != null && scrollPos.maxScrollExtent >= 0) {
      _scrollController.jumpTo(scrollPos.maxScrollExtent);
      _onMessageListScroll();
      await _invokeMarkSeenNearBottom();
      if (mounted) {
        setState(() => _viewportScrollDone = true);
      }
      return;
    }

    if (pass < 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _viewportScrollAttempt(firstUnreadMessageId, messagesEmpty, pass + 1);
      });
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final messages = widget.messages;
    final showListContent = !widget.hasError || messages.isNotEmpty;

    return Column(
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
                        ListView.builder(
                          controller: _scrollController,
                          // Small gap so the last bubble (notably a full-width
                          // poll) doesn't sit flush against the composer, which
                          // made its tap target compete with the text field.
                          padding: const EdgeInsets.only(bottom: kSpacingSmall),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            final m = messages[i];
                            final prev =
                                i == 0 ? null : messages[i - 1];
                            final next = i + 1 >= messages.length
                                ? null
                                : messages[i + 1];
                            final dateChanged = prev == null ||
                                !roomMessageSameLocalDay(
                                  prev.createdAt,
                                  m.createdAt,
                                );
                            final idxUnread = widget.firstUnreadIndex;
                            final unreads = widget.unreadCount;
                            final showUnreadBand = unreads > 0 &&
                                idxUnread >= 0 &&
                                i == idxUnread;

                            final toggle = widget.onToggleReaction;
                            final vote = widget.onVotePoll;
                            final messageTile = RoomMessageTile(
                              key: _messageKey(m.id),
                              message: m,
                              myProfile: widget.myProfile,
                              previousMessage: prev,
                              nextMessage: next,
                              breakGroupAbove: dateChanged || showUnreadBand,
                              onActionsPressed: widget.onMessageActions,
                              onToggleReaction:
                                  toggle ?? ((_, _) async {}),
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
                              onScrollToPromoteSource: widget.onScrollToPromoteSource,
                              onOpenCoordinationItem: widget.onOpenCoordinationItem,
                              hideCoordinationLifecycleFooter:
                                  widget.hideCoordinationLifecycleFooter,
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
                        if (_showJumpFab)
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
    );
  }

  Widget _buildComposerRow(BuildContext context) {
    final repo = widget.imageRepository;
    final onSend = widget.onSend;
    final canCompose = repo != null && onSend != null;

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
                        imageRepository: repo,
                        isSending: widget.isLoading,
                        onSend: onSend,
                        enableAttachments: widget.enableComposerAttachments,
                        enableParticipantMentions:
                            widget.enableParticipantMentions,
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
    required this.isSending,
    required this.onSend,
    this.enableAttachments = true,
    this.enableParticipantMentions = true,
    super.key,
  });

  final ImageRepository imageRepository;

  final bool isSending;

  final Future<void> Function(String body, List<RoomPendingUpload> uploads)
      onSend;

  final bool enableAttachments;

  final bool enableParticipantMentions;

  @override
  State<BeaconRoomComposer> createState() => _BeaconRoomComposerState();
}

class _BeaconRoomComposerState extends State<BeaconRoomComposer> {
  final _text = MentionTextController();
  final _composerFocus = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<BeaconParticipant> _overlaySuggestions = const [];
  var _overlaySyncScheduled = false;

  final List<RoomPendingUpload> _pending = [];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _composerFocus.addListener(_onComposerFocusChange);
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

  void _onTextChanged() {
    if (!mounted) return;
    _scheduleOverlaySync();
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
    if (!widget.enableParticipantMentions) {
      _removeOverlay();
      return;
    }
    final query = _text.activeMentionQuery;
    if (query == null) {
      _removeOverlay();
      return;
    }
    final cubit = context.read<RoomCubit>();
    final suggestions = cubit.state
        .participantsMatchingQuery(query)
        .where((p) => p.handle.isNotEmpty)
        .take(5)
        .toList(growable: false);
    if (suggestions.isEmpty) {
      _removeOverlay();
      return;
    }
    _showOverlay(suggestions);
  }

  void _removeOverlay() {
    _overlaySuggestions = const [];
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(List<BeaconParticipant> suggestions) {
    _overlaySuggestions = suggestions;
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (_) {
        final list = _overlaySuggestions;
        if (list.isEmpty) return const SizedBox.shrink();
        return MentionSuggestionsOverlay(
          suggestions: list,
          layerLink: _layerLink,
          onDismiss: _removeOverlay,
          onSelect: (p) {
            _text.insertMention(p.handle.toLowerCase());
            _removeOverlay();
          },
        );
      },
    );
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    overlay?.insert(_overlayEntry!);
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
    final result = await FilePicker.pickFiles(
      
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    for (final pf in result.files) {
      if (_remainingSlots <= 0) {
        break;
      }
      final bytes = await pf.readAsBytes();
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
      _removeOverlay();
      _text.clear();
      setState(_pending.clear);
    } on Object catch (_) {}
  }

  /// Once the composer gains focus, ensure the platform text input connection
  /// opens on the next frame (after layout). Poll sliders used to hold primary
  /// focus and leave the composer with a cursor but no keyboard; [ExcludeFocus]
  /// on [RoomPollCard] voting controls prevents that, and this covers any
  /// remaining focus→connection timing gap (EditableText #126312).
  void _onComposerFocusChange() {
    if (!_composerFocus.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_composerFocus.hasFocus) {
        return;
      }
      _composerEditableText()?.requestKeyboard();
    });
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
        if (widget.enableAttachments && _pending.isNotEmpty)
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
            if (widget.enableAttachments)
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
              child: CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _text,
                  focusNode: _composerFocus,
                  decoration: InputDecoration(
                    hintText: l10n.beaconRoomMessageHint,
                  ),
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  enabled: !busy,
                  onSubmitted: (_) => unawaited(_submit()),
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
