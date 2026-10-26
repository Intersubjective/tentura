import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

import '../bloc/beacon_create_cubit.dart';
import 'beacon_create_screen.dart' show popCreateAndOpenLiveBeacon;

/// «Новый пост» (a new Post, #248, #720): a short form in two steps, like a
/// simplified Request form.
/// First the Post itself — text, photos and files, whether it may be
/// forwarded; then «Получатели», where «Отправить» publishes it to the people
/// chosen.
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

  /// The Post text field on the first step.
  static const textFieldKey = Key('PostCreate.Text');

  /// «Далее: получатели» on the first step.
  static const nextButtonKey = Key('PostCreate.Next');

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

class _PostCreateScreenState extends State<PostCreateScreen>
    with PendingAttachmentsMixin {
  late final BeaconCreateCubit _createCubit;

  final _text = TextEditingController();
  late final _textFocus = FocusNode(onKeyEvent: _onTextKey);

  var _onRecipientsStep = false;
  var _forwardable = true;
  var _hasContent = false;

  @override
  ImageRepository get attachmentImageRepository => GetIt.I<ImageRepository>();

  @override
  ClipboardImageRepository get attachmentClipboardRepository =>
      GetIt.I<ClipboardImageRepository>();

  @override
  void onPendingUploadsChanged() => _reportContent();

  @override
  void initState() {
    super.initState();
    _createCubit = context.read<BeaconCreateCubit>();
    _text.addListener(_reportContent);
  }

  @override
  void dispose() {
    // A draft not yet made must not outlive the screen.
    _createCubit.postContentChanged(hasContent: false);
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _reportContent() {
    final hasContent =
        _text.text.trim().isNotEmpty || pendingUploads.isNotEmpty;
    if (hasContent == _hasContent || !mounted) return;
    _createCubit.postContentChanged(hasContent: hasContent);
    setState(() => _hasContent = hasContent);
  }

  /// Ctrl/Cmd+V also attaches a copied image; the field still pastes text.
  KeyEventResult _onTextKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        isPasteShortcutPressed() &&
        !_createCubit.state.isLoading) {
      unawaited(pasteImageAttachment(fromKeyboard: true));
    }
    return KeyEventResult.ignored;
  }

  void _showRecipients() {
    if (!_hasContent) return;
    _textFocus.unfocus();
    setState(() => _onRecipientsStep = true);
  }

  void _showForm() => setState(() => _onRecipientsStep = false);

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

  Future<void> _send() async {
    final cubit = _createCubit;
    final sent = await cubit.publishPost(
      body: _text.text,
      mentions: const [],
      forwardCubit: context.read<ForwardCubit>(),
      forwardPolicy: _forwardable
          ? BeaconForwardPolicyValue.open
          : BeaconForwardPolicyValue.closed,
      attachments: List.of(pendingUploads),
    );
    final id = cubit.state.draftId;
    if (sent && mounted && id != null) {
      widget.onPublished?.call();
      await popCreateAndOpenLiveBeacon(context.router, beaconId: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final onRecipients = _onRecipientsStep;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_onRecipientsStep) {
          _showForm();
        } else {
          unawaited(_close());
        }
      },
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          title: Text(
            onRecipients ? l10n.beaconRecipients : l10n.postsTabNewPost,
          ),
          leading: onRecipients
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _showForm,
                )
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => unawaited(_close()),
                ),
          actions: [
            if (onRecipients)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => unawaited(_close()),
              )
            else
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
        bottomNavigationBar: onRecipients ? null : _nextBar(context, l10n),
        body: SafeArea(
          child: TenturaContentColumn(
            child: BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
              selector: (state) => state.isLoading,
              builder: (context, busy) => onRecipients
                  ? _recipientsStep(context, l10n, busy: busy)
                  : _formStep(context, l10n, busy: busy),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formStep(BuildContext context, L10n l10n, {required bool busy}) {
    final tt = context.tt;
    final canAttach = !busy && remainingAttachmentSlots > 0;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.sectionGap,
      ),
      children: [
        TextField(
          key: PostCreateScreen.textFieldKey,
          controller: _text,
          focusNode: _textFocus,
          enabled: !busy,
          autofocus: true,
          minLines: 6,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: l10n.postCreateTextHint,
            border: const OutlineInputBorder(),
          ),
        ),
        if (pendingUploads.isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          Wrap(
            spacing: tt.rowGap,
            runSpacing: tt.rowGap,
            children: [
              for (var i = 0; i < pendingUploads.length; i++)
                PendingAttachmentPreview(
                  upload: pendingUploads[i],
                  onRemove: busy ? null : () => removePendingUpload(i),
                ),
            ],
          ),
        ],
        SizedBox(height: tt.tightGap),
        Wrap(
          spacing: tt.rowGap,
          children: [
            TextButton.icon(
              onPressed: canAttach
                  ? () => unawaited(pickImageAttachments())
                  : null,
              icon: const Icon(Icons.photo_outlined),
              label: Text(l10n.beaconRoomAttachPickImages),
            ),
            TextButton.icon(
              onPressed: canAttach
                  ? () => unawaited(pickFileAttachments())
                  : null,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(l10n.beaconRoomAttachPickFiles),
            ),
            TextButton.icon(
              onPressed: canAttach
                  ? () => unawaited(pasteImageAttachment())
                  : null,
              icon: const Icon(Icons.content_paste_rounded),
              label: Text(l10n.beaconRoomAttachPasteImage),
            ),
          ],
        ),
        SizedBox(height: tt.rowGap),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.postCreateAllowForwarding),
          subtitle: Text(
            _forwardable
                ? l10n.postCreateForwardingOnHint
                : l10n.postCreateForwardingOffHint,
          ),
          value: _forwardable,
          onChanged: busy
              ? null
              : (value) => setState(() => _forwardable = value),
        ),
      ],
    );
  }

  Widget _recipientsStep(
    BuildContext context,
    L10n l10n, {
    required bool busy,
  }) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
    child: BlocSelector<ForwardCubit, ForwardState, bool>(
      selector: (state) => state.selectedIds.isNotEmpty,
      builder: (context, hasRecipients) => ForwardRecipientPicker(
        beaconId: '',
        embedded: true,
        sendEnabled: hasRecipients && !busy,
        externalActionLoading: busy,
        sendLabel: l10n.postCreateSendToCount,
        promptUncoveredNotes: false,
        copyProfile: ForwardTargetProfile.post,
        recipientNoteHint: l10n.beaconCreateRecipientNoteHint,
        onSendPressed: () => unawaited(_send()),
      ),
    ),
  );

  /// «Далее: получатели», sitting in the form's column like the Request form.
  Widget _nextBar(BuildContext context, L10n l10n) {
    final tt = context.tt;
    return Material(
      color: tt.surface,
      child: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tt.contentMaxWidth ?? double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                tt.cardPadding.top,
                tt.screenHPadding,
                tt.sectionGap,
              ),
              child: SizedBox(
                height: tt.buttonHeight,
                width: double.infinity,
                child: FilledButton(
                  key: PostCreateScreen.nextButtonKey,
                  onPressed: _hasContent ? _showRecipients : null,
                  child: Text(l10n.beaconCreateNextRecipients),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
