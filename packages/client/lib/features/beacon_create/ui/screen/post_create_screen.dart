import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_threads/domain/entity/committed_mention.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../bloc/beacon_create_cubit.dart';

/// «Новый пост»: an empty room. A Post has no form — the first message the
/// author writes is the Post, sent to the people chosen in «Кому».
@RoutePage()
class PostCreateScreen extends StatefulWidget implements AutoRouteWrapper {
  const PostCreateScreen({
    @QueryParam(kQueryBeaconForwardTo) this.forwardToUserId = '',
    this.initialRecipientIds = const <String>{},
    this.onRecipientsChanged,
    this.onPublished,
    super.key,
  });

  /// Optional profile-route recipient to preselect.
  final String forwardToUserId;

  /// Recipients preselected by the map composer's radius selection.
  final Set<String> initialRecipientIds;

  final void Function(Set<String>, Map<String, String>)? onRecipientsChanged;
  final VoidCallback? onPublished;

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => BeaconCreateCubit(kind: BeaconKind.post)),
      BlocProvider(
        create: (_) => ForwardCubit(
          beaconId: '',
          embedded: true,
          initialSelectedIds: {
            ...initialRecipientIds,
            if (forwardToUserId.isNotEmpty) forwardToUserId,
          },
        ),
      ),
    ],
    child: this,
  );
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  late final BeaconCreateCubit _createCubit;

  var _forwardable = true;
  var _hasContent = false;

  @override
  void initState() {
    super.initState();
    _createCubit = context.read<BeaconCreateCubit>();
  }

  @override
  void dispose() {
    // A draft not yet made must not outlive the screen.
    _createCubit.postContentChanged(hasContent: false);
    super.dispose();
  }

  void _onContentChanged(bool hasContent) {
    _createCubit.postContentChanged(hasContent: hasContent);
    if (mounted) setState(() => _hasContent = hasContent);
  }

  Future<void> _close() async {
    final l10n = L10n.of(context)!;
    if (_hasContent) {
      final discard = await TenturaConfirmDialog.show(
        context: context,
        title: l10n.postCreateDiscardTitle,
        content: l10n.postCreateDiscardBody,
        confirmLabel: l10n.buttonDelete,
        cancelLabel: l10n.buttonCancel,
        emphasizeCancel: true,
      );
      if (discard != true || !mounted) return;
    }
    if (_createCubit.hasPostDraft) await _createCubit.discardPost();
    if (!mounted) return;
    final forward = context.read<ForwardCubit>().state;
    widget.onRecipientsChanged?.call(
      {...forward.selectedIds},
      {...forward.perRecipientNotes},
    );
    // PopScope.canPop is false, so maybePop would re-enter this method; a
    // direct pop bypasses it. A deep-linked screen has nothing to pop to.
    final route = ModalRoute.of(context);
    if (route != null && !route.isFirst) {
      Navigator.of(context).pop();
    } else {
      await context.router.navigatePath(kPathMyWork);
    }
  }

  Future<void> _pickRecipients() => showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) => BlocProvider.value(
      value: context.read<ForwardCubit>(),
      child: ForwardRecipientPicker(
        beaconId: '',
        embedded: true,
        sendEnabled: true,
        onSendPressed: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );

  Future<bool> _send(
    String body,
    List<RoomPendingUpload> uploads,
    List<CommittedMention> mentions,
  ) async {
    final cubit = _createCubit;
    final sent = await cubit.publishPost(
      body: body,
      mentions: mentions,
      forwardCubit: context.read<ForwardCubit>(),
      forwardPolicy: _forwardable
          ? BeaconForwardPolicyValue.open
          : BeaconForwardPolicyValue.closed,
      attachments: uploads,
    );
    final id = cubit.state.draftId;
    if (sent && mounted && id != null) {
      widget.onPublished?.call();
      await context.router.popAndPush(BeaconViewRoute(id: id));
    }
    return sent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          title: Text(l10n.postsTabNewPost),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => unawaited(_close()),
          ),
          actions: [
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              itemBuilder: (_) => [
                PopupMenuItem<void>(
                  onTap: () => context.read<ScreenCubit>().showBeaconCreate(),
                  child: Text(l10n.postCreateNeedHelp),
                ),
              ],
            ),
          ],
          progress: BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
            selector: (state) => state.isLoading,
            builder: TenturaTopBar.loadingBar,
          ),
        ),
        body: SafeArea(
          child: TenturaContentColumn(
            child: BlocBuilder<ForwardCubit, ForwardState>(
              buildWhen: (p, c) =>
                  p.selectedIds != c.selectedIds ||
                  p.candidates != c.candidates,
              builder: (context, forward) => Column(
                children: [
                  ListTile(
                    title: Text(_recipientsLabel(l10n, forward)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => unawaited(_pickRecipients()),
                  ),
                  SwitchListTile(
                    title: Text(l10n.postCreateAllowForwarding),
                    subtitle: Text(
                      _forwardable
                          ? l10n.postCreateForwardingOnHint
                          : l10n.postCreateForwardingOffHint,
                    ),
                    value: _forwardable,
                    onChanged: (value) => setState(() => _forwardable = value),
                  ),
                  Expanded(
                    child: BasicChatBody(
                      messages: const [],
                      myProfile: context.read<ProfileCubit>().state.profile,
                      participants: _mentionable(forward),
                      isLoading: false,
                      onSend: (body, uploads) => _send(body, uploads, const []),
                      onSendWithMentions: _send,
                      imageRepository: GetIt.I<ImageRepository>(),
                      clipboardImageRepository:
                          GetIt.I<ClipboardImageRepository>(),
                      composerSendEnabled: _hasContent,
                      onComposerContentChanged: _onContentChanged,
                      emptyPlaceholder: Center(
                        child: Padding(
                          padding: EdgeInsets.all(tt.sectionGap),
                          child: Text(
                            l10n.postCreateEmptyHint,
                            textAlign: TextAlign.center,
                            style: TenturaText.body(tt.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _recipientsLabel(L10n l10n, ForwardState forward) {
    final selected = forward.selectedIds;
    if (selected.isEmpty) return l10n.postCreateRecipientsEmpty;
    final names = [
      for (final candidate in forward.candidates)
        if (selected.contains(candidate.id)) candidate.displayName,
    ];
    return names.isEmpty
        ? l10n.postCreateRecipientsCount(selected.length)
        : l10n.postCreateRecipients(names.join(', '));
  }

  /// The people a Post is sent to are who the author can @mention in it.
  static List<BeaconParticipant> _mentionable(ForwardState forward) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return [
      for (final candidate in forward.candidates)
        if (forward.selectedIds.contains(candidate.id))
          BeaconParticipant(
            id: candidate.id,
            beaconId: '',
            userId: candidate.id,
            role: 0,
            status: 0,
            roomAccess: 0,
            createdAt: epoch,
            updatedAt: epoch,
            userTitle: candidate.displayName,
            handle: candidate.profile.handle,
          ),
    ];
  }
}
