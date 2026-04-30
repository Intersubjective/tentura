import 'dart:async';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/room_cubit.dart';
import '../widget/beacon_room_you_strip.dart';
import '../widget/room_facts_sheet.dart';
import '../widget/room_message_tile.dart';
import '../widget/room_now_strip.dart';

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
          listeners: const [
            BlocListener<ScreenCubit, ScreenState>(
              listener: commonScreenBlocListener,
            ),
            BlocListener<RoomCubit, RoomState>(
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
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final myProfile = GetIt.I<ProfileCubit>().state.profile;

    return BlocBuilder<RoomCubit, RoomState>(
      buildWhen: (p, c) =>
          p.messages != c.messages ||
          p.factCards.length != c.factCards.length ||
          p.roomState?.currentPlan != c.roomState?.currentPlan ||
          p.roomState?.lastRoomMeaningfulChange !=
              c.roomState?.lastRoomMeaningfulChange ||
          p.roomState?.openBlockerId != c.roomState?.openBlockerId ||
          p.roomState?.openBlockerTitle != c.roomState?.openBlockerTitle ||
          p.participants.length != c.participants.length ||
          p.participants.map((e) => '${e.userId}|${e.nextMoveText}').join() !=
              c.participants.map((e) => '${e.userId}|${e.nextMoveText}').join() ||
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                final router = context.router;
                if (router.canPop()) {
                  unawaited(router.maybePop());
                } else {
                  unawaited(
                    router.navigatePath(
                      '$kPathBeaconView/${widget.beaconId}',
                    ),
                  );
                }
              },
            ),
            title: Text(l10n.beaconRoomTitle),
            actions: [
              IconButton(
                tooltip: l10n.beaconFactsOpenTooltip,
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () => unawaited(
                  showRoomFactsSheet(context, facts: state.factCards),
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
                ),
              BeaconRoomYouStrip(
                myParticipant: myRow,
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
                    : ListView.builder(
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) => RoomMessageTile(
                          message: state.messages[i],
                          myProfile: myProfile,
                          onActionsPressed: (m) =>
                              _onMessageActionsPressed(context, cubit, l10n, m),
                          onToggleReaction: (messageId, emoji) =>
                              cubit.toggleReaction(
                                messageId: messageId,
                                emoji: emoji,
                              ),
                          onOpenFileAttachment: (a) => unawaited(
                            _openRoomFileAttachment(context, cubit, l10n, a),
                          ),
                        ),
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
    );
  }

  void _onMessageActionsPressed(
    BuildContext context,
    RoomCubit cubit,
    L10n l10n,
    RoomMessage message,
  ) {
    unawaited(
      showModalBottomSheet<void>(
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
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(l10n.beaconRoomActionPinFact),
                onTap: () {
                  Navigator.pop(ctx);
                  final text = message.body.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.beaconRoomPinFactDisabledEmpty),
                      ),
                    );
                    return;
                  }
                  unawaited(
                    _showPinFactChoices(context, cubit, l10n, message, text),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_problem_outlined),
                title: Text(l10n.beaconRoomActionMarkBlocker),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_showMarkBlockerSheet(context, cubit, l10n, message));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(l10n.beaconRoomActionNeedInfo),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_showNeedInfoSheet(context, cubit, l10n, message));
                },
              ),
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(l10n.beaconRoomActionMarkDone),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_showMarkDoneSheet(context, cubit, l10n, message));
                },
              ),
            ],
          ),
        ),
      ),
    );
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
                  decoration: InputDecoration(hintText: l10n.beaconRoomStripPlanLabel),
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
            decoration: InputDecoration(hintText: l10n.beaconRoomBlockerTitleHint),
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
                          p.userId.length <= 16
                              ? p.userId
                              : '${p.userId.substring(0, 14)}…',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => targetUserId = v ?? targetUserId),
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
                  onlyBlocker &&
                          (rs.openBlockerTitle ?? '').trim().isNotEmpty
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
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: name,
          mimeType: attachment.mime,
        ),
      ]);
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
    final mb = kMaxRoomMessageAttachmentBytes ~/ (1024 * 1024);
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
      final mime = pf.extension != null && pf.extension!.trim().isNotEmpty
          ? _mimeFromExtension(pf.extension!)
          : 'application/octet-stream';
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
      setState(() => _pending.clear());
    } on Object catch (_) {}
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
                      child: InputChip(
                        label: Text(
                          _pending[i].fileName.trim().isEmpty
                              ? l10n.beaconRoomAttachmentUntitled
                              : _pending[i].fileName,
                          style: theme.textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: busy
                            ? null
                            : () => setState(() => _pending.removeAt(i)),
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
