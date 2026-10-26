import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart' show showSnackBar;
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../bloc/beacon_create_cubit.dart';
import '../dialog/beacon_send_confirmation_dialog.dart';
import '../widget/info_tab.dart';
import '../widget/post_bud_invite_step.dart';
import '../widget/recipients_tab.dart';

/// After a successful send, leave the composer and open the published request
/// or post. The pop goes through the Navigator, so a caller awaiting the
/// composer's push still gets its result. The room's URL then replaces the
/// composer's browser history entry, so Back does not reopen an empty composer
/// (#353); `popAndPush` would add it as a new entry instead.
Future<void> popCreateAndOpenLiveBeacon(
  StackRouter router, {
  required String beaconId,
}) async {
  router
    ..pop()
    ..markUrlStateForReplace();
  await router.push(BeaconViewRoute(id: beaconId));
}

BeaconCreationContext? _childCreationContext({
  required String parentBeaconId,
  required String sourceMessageId,
}) {
  final parent = parentBeaconId.trim();
  if (parent.isEmpty) return null;
  final source = sourceMessageId.trim();
  if (source.isNotEmpty) {
    return BeaconCreationContextPromotedChild(
      parentBeaconId: parent,
      sourceMessageId: source,
    );
  }
  return BeaconCreationContextChild(parentBeaconId: parent);
}

@RoutePage()
class BeaconCreateScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconCreateScreen({
    @QueryParam(kQueryBeaconDraftId) this.draftId = '',
    @QueryParam(kQueryBeaconEditId) this.editId = '',
    @QueryParam(kQueryBeaconCreateTab) this.initialTab = '',
    @QueryParam(kQueryBeaconForwardTo) this.forwardToUserId = '',
    @QueryParam(kQueryBeaconParentId) this.parentBeaconId = '',
    @QueryParam(kQueryBeaconSourceMessageId) this.sourceMessageId = '',
    @QueryParam(kQueryBeaconForkFrom) this.forkSourceId = '',
    @QueryParam(kQueryBeaconForkPlan) this.forkPlanTimes = '',
    this.initialRecipientIds = const {},
    this.initialNotes = const {},
    this.onRecipientsChanged,
    this.onPublished,
    super.key,
  });

  /// Line under «Publish without sending» saying who can see the Request.
  static const publishHintKey = Key('BeaconCreate.PublishWithoutSendingHint');

  /// Recipients preselected on the Recipients tab (graph composer hand-off).
  final Set<String> initialRecipientIds;

  /// Per-recipient notes for [initialRecipientIds].
  final Map<String, String> initialNotes;

  final void Function(Set<String>, Map<String, String>)? onRecipientsChanged;
  final VoidCallback? onPublished;

  /// Server draft beacon id when opening from My Work / deep link.
  final String draftId;

  /// Server open beacon id when editing a published beacon.
  final String editId;

  /// Optional initial focus: [kBeaconCreateTabRecipients] or
  /// [kBeaconCreateTabImage] (Cover editor on the form step).
  final String initialTab;

  /// Optional profile-route recipient to preselect when Recipients is prepared.
  final String forwardToUserId;

  /// Parent request when creating a nested child.
  final String parentBeaconId;

  /// General message to promote into a child request.
  final String sourceMessageId;

  /// «Create from this request» (#493): the request this editor copies. The
  /// server draft is forked from it only at the first edit or save.
  final String forkSourceId;

  /// Plan step times chosen for the copy, as [encodePlanStepTimesQuery]
  /// writes them into the URL (#607); empty copies no plan.
  final String forkPlanTimes;

  @override
  State<BeaconCreateScreen> createState() => _BeaconCreateScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ContextCubit(),
      ),
      BlocProvider(
        create: (_) => BeaconCreateCubit(
          draftBeaconIdToLoad: draftId.isEmpty ? null : draftId,
          editBeaconIdToLoad: editId.isEmpty ? null : editId,
          forkSourceIdToLoad: forkSourceId.isEmpty ? null : forkSourceId,
          forkPlanStepTimes: decodePlanStepTimesQuery(forkPlanTimes),
          forkTitle: L10n.of(context)!.beaconCopyOfTitle,
          childCreationContext: _childCreationContext(
            parentBeaconId: parentBeaconId,
            sourceMessageId: sourceMessageId,
          ),
        ),
      ),
    ],
    child: this,
  );
}

class _BeaconCreateScreenState extends State<BeaconCreateScreen> {
  static const _formStep = 0;
  static const _recipientsStep = 1;

  /// How long the recipients step waits for the draft before offering a retry.
  static const _draftEnsureTimeout = Duration(seconds: 90);

  final _formKey = GlobalKey<FormState>();

  late final _beaconCreateCubit = context.read<BeaconCreateCubit>();

  late int _step = widget.initialTab == kBeaconCreateTabRecipients
      ? _recipientsStep
      : _formStep;

  ForwardCubit? _forwardCubit;
  String? _forwardCubitDraftId;
  bool _recipientsDraftEnsuring = false;
  bool _leaveInProgress = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == kBeaconCreateTabRecipients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openRecipientsStep());
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_forwardCubit?.close());
    super.dispose();
  }

  Future<void> _openRecipientsStep() async {
    if (!mounted || _beaconCreateCubit.state.isEditMode) return;
    await _prepareRecipientsTab();
    if (mounted) {
      setState(() => _step = _recipientsStep);
    }
  }

  Future<void> _prepareRecipientsTab() async {
    if (_beaconCreateCubit.state.isEditMode || _recipientsDraftEnsuring) {
      return;
    }
    _formKey.currentState?.save();
    _beaconCreateCubit.validate();
    if (_beaconCreateCubit.state.publishBlocker != null) {
      return;
    }
    final contextName = context.read<ContextCubit>().state.selected;
    setState(() => _recipientsDraftEnsuring = true);
    try {
      await _flushAndEnsureDraft(contextName).timeout(_draftEnsureTimeout);
    } on TimeoutException {
      // The create stays in flight: a late answer still sets draftId and
      // opens the picker.
    }
    if (mounted) {
      setState(() => _recipientsDraftEnsuring = false);
    }
  }

  Future<void> _flushAndEnsureDraft(String contextName) async {
    // Flush before the forward band loads: needs selected after the first
    // autosave must reach the server or fetchForwardContext sees empty needs
    // and returns an empty band (no "Seen helping with …").
    await _beaconCreateCubit.flushAutosave();
    if (_beaconCreateCubit.state.draftId != null) {
      return;
    }
    await _beaconCreateCubit.ensureDraft(
      context: contextName,
      showMessage: false,
    );
  }

  ForwardCubit? _forwardCubitFor(BeaconCreateState state, String contextName) {
    final id = state.draftId;
    if (id == null || id.isEmpty || state.isEditMode) {
      return null;
    }
    if (_forwardCubitDraftId != id) {
      unawaited(_forwardCubit?.close());
      _forwardCubit = ForwardCubit(
        beaconId: id,
        context: contextName,
        preselectLineageSuggestions:
            state.lineageParentBeaconId != null &&
            state.lineageParentBeaconId!.isNotEmpty,
        initialSelectedIds: widget.forwardToUserId.isEmpty
            ? widget.initialRecipientIds
            : {widget.forwardToUserId},
        initialNotes: widget.initialNotes,
        embedded: true,
      );
      _forwardCubitDraftId = id;
    }
    return _forwardCubit;
  }

  Future<void> _makeLive() async {
    final contextName = context.read<ContextCubit>().state.selected;
    await _beaconCreateCubit.makeLive(context: contextName);
    if (!mounted || !_beaconCreateCubit.state.isLive) return;
    final id = _beaconCreateCubit.state.draftId;
    if (id == null || id.isEmpty) return;
    widget.onPublished?.call();
    await popCreateAndOpenLiveBeacon(context.router, beaconId: id);
  }

  /// Buds the Request, opens it, and names the picked members the server
  /// did not invite.
  Future<void> _submitBud() async {
    final contextName = context.read<ContextCubit>().state.selected;
    final l10n = L10n.of(context)!;
    final bud = _beaconCreateCubit.state.postBud;
    final result = await _beaconCreateCubit.submitBud(context: contextName);
    if (!mounted || result == null) return;
    final childId = result.childBeaconId;
    final skipped = result.notInvitedUserIds;
    if (skipped.isNotEmpty) {
      final names = [
        for (final id in skipped)
          switch (bud?.nameOf(id) ?? '') {
            '' => l10n.unknownPerson,
            final name => name,
          },
      ].join(', ');
      showSnackBar(context, text: l10n.postBudNotInvitedSnack(names));
    }
    if (childId == null || childId.isEmpty) return;
    widget.onPublished?.call();
    await popCreateAndOpenLiveBeacon(context.router, beaconId: childId);
  }

  Future<void> _sendRequest() async {
    final contextName = context.read<ContextCubit>().state.selected;
    _formKey.currentState?.save();
    _beaconCreateCubit.validate();
    final forwardCubit = _forwardCubitFor(
      _beaconCreateCubit.state,
      contextName,
    );
    if (forwardCubit == null) {
      await _prepareRecipientsTab();
    }
    final cubit = _forwardCubitFor(_beaconCreateCubit.state, contextName);
    if (cubit == null || !mounted) return;

    final outcome = await _beaconCreateCubit.sendRequest(
      context: contextName,
      forwardCubit: cubit,
    );
    if (!mounted || outcome == null) return;

    await BeaconSendConfirmationDialog.show(context, outcome: outcome);
    if (!mounted) return;
    if (!outcome.failed) {
      final id = _beaconCreateCubit.state.draftId;
      if (id == null || id.isEmpty) return;
      widget.onPublished?.call();
      await popCreateAndOpenLiveBeacon(context.router, beaconId: id);
    }
  }

  /// Whether leaving the info step should ask «Keep draft» / «Discard»
  /// (#428): only a request that is or can become a draft, and only once the
  /// form holds something.
  bool get _hasDraftContent {
    final s = _beaconCreateCubit.state;
    if (s.isEditMode || s.isLive || s.isPostBud) return false;
    // A copy left as it opened has nothing to keep (#493).
    if (_beaconCreateCubit.isUntouchedCopy) return false;
    return s.title.trim().isNotEmpty ||
        s.description.trim().isNotEmpty ||
        (s.draftId?.isNotEmpty ?? false);
  }

  /// Leaves the create flow. The recipients-step «✕» keeps the draft without
  /// asking (#265); the info step's single exit («←» or system back) passes
  /// [askAboutDraft] so the user picks «Keep draft» or «Discard» (#428).
  /// Dismissing the question keeps the editor open.
  Future<void> _leaveForm({bool askAboutDraft = false}) async {
    if (_leaveInProgress) return;
    _leaveInProgress = true;
    try {
      _formKey.currentState?.save();
      if (askAboutDraft &&
          _hasDraftContent &&
          !_beaconCreateCubit.keepsDraftOnLeave) {
        // Too little for a draft (#607): «Keep draft» would keep nothing.
        final l10n = L10n.of(context)!;
        final discard = await TenturaConfirmDialog.show(
          context: context,
          title: l10n.beaconCreateLeaveUnsavedTitle,
          content: l10n.beaconCreateLeaveUnsavedBody,
          confirmLabel: l10n.beaconCreateLeaveUnsavedDiscard,
          cancelLabel: l10n.beaconCreateLeaveKeepEditing,
          emphasizeCancel: true,
        );
        if (discard != true || !mounted) return;
        await _beaconCreateCubit.discardDraft();
        if (!mounted) return;
        await _exitFlow();
        return;
      }
      if (askAboutDraft && _hasDraftContent) {
        final l10n = L10n.of(context)!;
        final discard = await TenturaConfirmDialog.show(
          context: context,
          title: l10n.beaconCreateLeaveTitle,
          content: l10n.beaconCreateLeaveBody,
          confirmLabel: l10n.beaconCreateLeaveDiscard,
          cancelLabel: l10n.beaconCreateLeaveKeepDraft,
          emphasizeCancel: true,
        );
        if (discard == null || !mounted) return;
        if (discard) {
          // Not deleteDraft(): its NavigateBack would maybePop into this
          // method again.
          await _beaconCreateCubit.discardDraft();
          if (!mounted) return;
          await _exitFlow();
          return;
        }
      }
      await _beaconCreateCubit.flushAutosave();
      if (!mounted) return;
      await _exitFlow();
    } finally {
      if (mounted) _leaveInProgress = false;
    }
  }

  Future<void> _exitFlow() async {
    final forward = _forwardCubit?.state;
    widget.onRecipientsChanged?.call(
      {...(forward?.selectedIds ?? widget.initialRecipientIds)},
      {...(forward?.perRecipientNotes ?? widget.initialNotes)},
    );
    // PopScope.canPop is false, so maybePop re-enters _leaveForm. Pop
    // bypasses that guard; isFirst ignores PopScope for the deep-link case.
    final route = ModalRoute.of(context);
    if (route != null && !route.isFirst) {
      Navigator.of(context).pop();
    } else {
      await context.router.navigatePath(kPathMyWork);
    }
  }

  Future<void> _onNext() async {
    _formKey.currentState?.save();
    _beaconCreateCubit.validate();
    if (_beaconCreateCubit.state.publishBlocker != null) {
      _beaconCreateCubit.revealValidationHints();
      return;
    }
    if (_beaconCreateCubit.state.isPostBud) {
      // A bud saves nothing before submit: no draft, no recipients step.
      setState(() => _step = _recipientsStep);
      return;
    }
    await _beaconCreateCubit.flushAutosave();
    if (!mounted) return;
    await _openRecipientsStep();
  }

  Future<void> _onDraftMenu(String value) async {
    final contextName = context.read<ContextCubit>().state.selected;
    if (value == 'save') {
      _formKey.currentState?.save();
      await _beaconCreateCubit.saveDraft(context: contextName);
      return;
    }
    if (value == 'delete') {
      final confirmed = await BeaconDeleteDialog.show(
        context,
        status: BeaconStatus.draft,
        hasEverHadCommitter: false,
      );
      if (!(confirmed ?? false) || !mounted) return;
      // Leave here rather than through the cubit's NavigateBack, which would
      // maybePop into _leaveForm and ask «Keep this draft?» (#625).
      final deleted = await _beaconCreateCubit.deleteDraft(
        navigateBack: false,
      );
      if (deleted && mounted) await _exitFlow();
    }
  }

  Future<void> _openDraftMenu(
    BuildContext context,
    L10n l10n, {
    required bool hasDraft,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'save', child: Text(l10n.buttonSaveDraft)),
        if (hasDraft)
          PopupMenuItem(value: 'delete', child: Text(l10n.deleteBeacon)),
      ],
    );
    if (selected != null && context.mounted) {
      await _onDraftMenu(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final contextName = context.watch<ContextCubit>().state.selected;
    _beaconCreateCubit.setAutosaveContext(contextName);
    final isRecipients = _step == _recipientsStep;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step == _recipientsStep) {
          setState(() => _step = _formStep);
          return;
        }
        await _leaveForm(askAboutDraft: true);
      },
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          leading: isRecipients
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => setState(() => _step = _formStep),
                )
              : AutoLeadingWithFallback(
                  fallbackPath: kPathMyWork,
                  onPressed: () => unawaited(_leaveForm(askAboutDraft: true)),
                ),
          trailingIsIcon: false,
          title:
              BlocSelector<
                BeaconCreateCubit,
                BeaconCreateState,
                ({bool isDraft, bool isEdit, bool isLive, bool isBud})
              >(
                bloc: _beaconCreateCubit,
                selector: (s) => (
                  isDraft: s.draftId != null,
                  isEdit: s.isEditMode,
                  isLive: s.isLive,
                  isBud: s.isPostBud,
                ),
                // The title names the step, and a fresh request keeps
                // "Create new request" after autosave quietly made a draft —
                // it used to flip to "Edit draft" mid-typing (UI review).
                builder: (context, mode) => Text(
                  mode.isBud
                      ? (isRecipients
                            ? l10n.postBudInviteTitle
                            : l10n.postBudAction)
                      : isRecipients
                      ? l10n.beaconRecipients
                      : mode.isEdit
                      ? l10n.editBeaconTitle
                      : mode.isLive
                      ? l10n.liveRequestTitle
                      : mode.isDraft && widget.draftId.isNotEmpty
                      ? l10n.editDraftTitle
                      : l10n.createNewBeacon,
                ),
              ),
          actions: [
            // The info step has one exit, «←» (#428); «✕» only on the
            // recipients step, where «←» goes back a step (#265).
            if (isRecipients)
              IconButton(
                icon: Icon(Icons.close, semanticLabel: l10n.buttonClose),
                tooltip: l10n.buttonClose,
                onPressed: () => unawaited(_leaveForm()),
              ),
            if (!isRecipients)
              BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
                bloc: _beaconCreateCubit,
                buildWhen: (p, c) =>
                    p.isEditMode != c.isEditMode ||
                    p.isLive != c.isLive ||
                    p.isLoading != c.isLoading ||
                    p.draftId != c.draftId ||
                    p.isPostBud != c.isPostBud,
                builder: (context, state) {
                  if (state.isEditMode || state.isLive || state.isPostBud) {
                    return const SizedBox.shrink();
                  }
                  return TenturaTextAction(
                    label: l10n.beaconCreateDraftAction,
                    tone: TenturaTone.neutral,
                    onPressed: state.isLoading
                        ? null
                        : () => unawaited(
                            _openDraftMenu(
                              context,
                              l10n,
                              hasDraft: state.draftId != null,
                            ),
                          ),
                  );
                },
              ),
          ],
          progress: BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
            key: const Key('BeaconCreate.LoadIndicator'),
            bloc: _beaconCreateCubit,
            selector: (state) => state.isLoading,
            builder: TenturaTopBar.loadingBar,
          ),
        ),
        bottomNavigationBar: _bottomBar(context, l10n, tt, contextName),
        body: SafeArea(
          child: TenturaContentColumn(
            child: BlocListener<BeaconCreateCubit, BeaconCreateState>(
              bloc: _beaconCreateCubit,
              listenWhen: (p, c) =>
                  p.publishBlocker != c.publishBlocker ||
                  p.draftId != c.draftId,
              listener: (context, state) {
                if (!mounted) return;
                if (_step != _recipientsStep) return;
                if (state.isEditMode || state.isPostBud) return;
                if (state.publishBlocker != null) return;
                if (state.draftId != null) return;
                if (_recipientsDraftEnsuring) return;
                unawaited(_prepareRecipientsTab());
              },
              child: BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
                bloc: _beaconCreateCubit,
                buildWhen: (p, c) =>
                    p.status != c.status ||
                    p.draftId != c.draftId ||
                    p.isEditMode != c.isEditMode ||
                    p.isPostBud != c.isPostBud,
                builder: (context, state) {
                  if (state.isEditMode && _step != _formStep) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _step != _formStep) {
                        setState(() => _step = _formStep);
                      }
                    });
                  }
                  if ((widget.draftId.isNotEmpty && state.draftId == null ||
                          widget.editId.isNotEmpty && state.editId == null ||
                          widget.forkSourceId.isNotEmpty &&
                              state.forkSourceTitle.isEmpty) &&
                      state.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }
                  return Form(
                    key: _formKey,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: tt.screenHPadding,
                        top: tt.sectionGap * 2,
                        right: tt.screenHPadding,
                      ),
                      child:
                          BlocSelector<
                            BeaconCreateCubit,
                            BeaconCreateState,
                            bool
                          >(
                            key: const Key('BeaconCreate.FormBody'),
                            bloc: _beaconCreateCubit,
                            selector: (state) => state.isLoading,
                            builder: (context, isLoading) => AbsorbPointer(
                              absorbing: isLoading,
                              child: IndexedStack(
                                index: state.isEditMode ? _formStep : _step,
                                children: [
                                  InfoTab(
                                    key: const ValueKey('BeaconCreate.InfoTab'),
                                    openImagesInitially:
                                        widget.initialTab ==
                                        kBeaconCreateTabImage,
                                  ),
                                  if (state.isPostBud)
                                    const PostBudInviteStep()
                                  else
                                    _buildRecipientsTab(state, contextName),
                                ],
                              ),
                            ),
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(
    BuildContext context,
    L10n l10n,
    TenturaTokens tt,
    String contextName,
  ) {
    return Material(
      color: tt.surface,
      // The bar's content sits in the form's column; spanning the window
      // put the CTA 360 px wider than the fields it submits.
      child: SafeArea(
        // heightFactor 1: a bottom bar is as tall as its content.
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
              child: BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
                bloc: _beaconCreateCubit,
                builder: (context, state) {
                  if (state.isEditMode) {
                    return SizedBox(
                      height: tt.buttonHeight,
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('BeaconEdit.SaveChangesButton'),
                        onPressed: state.isLoading
                            ? null
                            : () async {
                                await _beaconCreateCubit.saveEdit(
                                  context: contextName,
                                );
                              },
                        child: _BusyLabel(
                          isSaving: state.isLoading,
                          label: l10n.buttonSaveChanges,
                        ),
                      ),
                    );
                  }

                  if (state.isPostBud) {
                    return _budBottomBar(state, l10n, tt);
                  }

                  if (_step == _recipientsStep) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const TenturaHairlineDivider(subtle: true),
                        SizedBox(height: tt.rowGap),
                        Row(
                          children: [
                            // Forwarding (the composer above) is this step's
                            // primary action; publishing without sending is
                            // the quiet escape hatch, not a second big CTA.
                            if (!state.isLive)
                              Expanded(
                                child: TextButton(
                                  key: TestIds.key(TestIds.requestMakeLive),
                                  onPressed:
                                      state.isLoading || !state.canTryToPublish
                                      ? null
                                      : () => unawaited(_makeLive()),
                                  child: _BusyLabel(
                                    isSaving: state.isLoading,
                                    label: l10n.beaconMakeLiveWithoutSending,
                                  ),
                                ),
                              ),
                            if (state.isLive)
                              Expanded(
                                child: SizedBox(
                                  height: tt.buttonHeight,
                                  child: FilledButton(
                                    key: const Key(
                                      'BeaconCreate.SaveChangesButton',
                                    ),
                                    onPressed: state.isLoading
                                        ? null
                                        : () async {
                                            await _beaconCreateCubit.saveEdit(
                                              context: contextName,
                                              navigateBack: false,
                                            );
                                          },
                                    child: _BusyLabel(
                                      isSaving: state.isLoading,
                                      label: l10n.buttonSaveChanges,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // The action publishes the Request (#440): say who
                        // can see it without being sent it.
                        if (!state.isLive) ...[
                          SizedBox(height: tt.tightGap),
                          Text(
                            state.isDiscoverable
                                ? l10n.beaconPublishWithoutSendingDiscoverableHint
                                // Members of the parent Request can read a
                                // child Request without being sent it.
                                : state.isChildMode && !state.isPostBud
                                ? l10n.beaconPublishWithoutSendingHiddenChildHint
                                : l10n.beaconPublishWithoutSendingHiddenHint,
                            key: BeaconCreateScreen.publishHintKey,
                            textAlign: TextAlign.center,
                            style: TenturaText.bodySmall(tt.textMuted),
                          ),
                        ],
                      ],
                    );
                  }

                  final valid = state.publishBlocker == null;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TenturaHairlineDivider(subtle: true),
                      SizedBox(height: tt.rowGap),
                      if (state.isLive)
                        SizedBox(
                          height: tt.buttonHeight,
                          width: double.infinity,
                          child: FilledButton(
                            key: const Key('BeaconCreate.SaveChangesButton'),
                            onPressed: state.isLoading
                                ? null
                                : () async {
                                    await _beaconCreateCubit.saveEdit(
                                      context: contextName,
                                      navigateBack: false,
                                    );
                                  },
                            child: _BusyLabel(
                              isSaving: state.isLoading,
                              label: l10n.buttonSaveChanges,
                            ),
                          ),
                        )
                      else
                        // Not-ready still answers a tap with validation, so it
                        // stays enabled but wears the neutral disabled colours
                        // instead of a 40 % washed-out brand (UI review #197).
                        SizedBox(
                          height: tt.buttonHeight,
                          width: double.infinity,
                          child: FilledButton(
                            key: TestIds.key(TestIds.requestRecipientsTab),
                            style: valid
                                ? null
                                : FilledButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            onPressed: state.isLoading
                                ? null
                                : () => unawaited(_onNext()),
                            child: Text(l10n.beaconCreateNextRecipients),
                          ),
                        ),
                      if (!state.isLive) ...[
                        SizedBox(height: tt.tightGap),
                        // The dimmed button still answers a tap with
                        // validation; this says what it waits for first.
                        if (state.publishBlocker != null)
                          Text(
                            switch (state.publishBlocker!) {
                              BeaconPublishBlocker.title =>
                                l10n.beaconCreateNextNeedsTitle,
                              BeaconPublishBlocker.description =>
                                l10n.beaconCreateNextNeedsDescription,
                            },
                            textAlign: TextAlign.center,
                            style: TenturaText.bodySmall(tt.textMuted),
                          )
                        else if (state.isAutosaving)
                          Text(
                            l10n.beaconCreateAutosaving,
                            style: TenturaText.bodySmall(tt.textFaint),
                          )
                        else if (state.lastAutosavedAt != null)
                          Text(
                            l10n.beaconCreateAutosavedJustNow,
                            style: TenturaText.bodySmall(tt.textFaint),
                          ),
                      ],
                      if (state.isLive) ...[
                        SizedBox(height: tt.rowGap),
                        SizedBox(
                          height: tt.buttonHeight,
                          width: double.infinity,
                          child: OutlinedButton(
                            key: TestIds.key(TestIds.requestRecipientsTab),
                            onPressed: () => unawaited(_openRecipientsStep()),
                            child: Text(l10n.beaconCreateNextRecipients),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bud mode: «Next» to the invite step, then «Оформить запрос».
  Widget _budBottomBar(
    BeaconCreateState state,
    L10n l10n,
    TenturaTokens tt,
  ) {
    final onInvites = _step == _recipientsStep;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TenturaHairlineDivider(),
        SizedBox(height: tt.rowGap),
        SizedBox(
          height: tt.buttonHeight,
          width: double.infinity,
          child: onInvites
              ? FilledButton(
                  key: const Key('PostBud.SubmitButton'),
                  onPressed:
                      state.isLoading ||
                          !(state.postBud?.candidatesLoaded ?? false)
                      ? null
                      : () => unawaited(_submitBud()),
                  child: _BusyLabel(
                    isSaving: state.isLoading,
                    label: l10n.postBudAction,
                  ),
                )
              : FilledButton(
                  key: const Key('PostBud.NextButton'),
                  onPressed: state.isLoading
                      ? null
                      : () => unawaited(_onNext()),
                  child: Text(l10n.buttonNext),
                ),
        ),
      ],
    );
  }

  Widget _buildRecipientsTab(BeaconCreateState state, String contextName) {
    final l10n = L10n.of(context)!;
    if (state.isEditMode) {
      return Center(
        child: Text(
          l10n.beaconSendRequestBlockedRecipients,
          textAlign: TextAlign.center,
          style: TenturaText.bodySmall(context.tt.textMuted),
        ),
      );
    }

    // IndexedStack keeps both steps mounted. Creating ForwardCubit while still
    // on the form step races the title-only draft autosave (empty needs) and
    // caches an empty forward band until the screen is rebuilt.
    if (_step != _recipientsStep) {
      return const SizedBox.shrink();
    }

    final draftId = state.draftId;
    if (draftId == null || draftId.isEmpty) {
      if (state.publishBlocker != null) {
        return const BeaconRecipientsBlockedTab();
      }
      if (_recipientsDraftEnsuring) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator.adaptive(),
              SizedBox(height: context.tt.rowGap),
              Text(
                l10n.beaconRecipientsPreparing,
                style: TenturaText.bodySmall(context.tt.textMuted),
              ),
            ],
          ),
        );
      }
    }
    if (draftId == null || draftId.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.beaconRecipientsPrepareFailed,
              style: TenturaText.bodySmall(context.tt.textMuted),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.tt.rowGap),
            TenturaCommandButton(
              key: const Key('BeaconCreate.RecipientsRetry'),
              label: l10n.myWorkRetry,
              onPressed: () => unawaited(_prepareRecipientsTab()),
            ),
          ],
        ),
      );
    }

    final forwardCubit = _forwardCubitFor(state, contextName)!;
    return BlocProvider.value(
      value: forwardCubit,
      child: BeaconRecipientsTab(
        beaconId: draftId,
        onSendRequest: () => unawaited(_sendRequest()),
      ),
    );
  }
}

/// Button label with an in-button spinner while the Request persists or
/// publishes, so a slow save reads as busy rather than an ignored tap
/// (GitHub #174, #242).
class _BusyLabel extends StatelessWidget {
  const _BusyLabel({
    required this.isSaving,
    required this.label,
  });

  final bool isSaving;

  final String label;

  @override
  Widget build(BuildContext context) {
    if (!isSaving) return Text(label);
    final tt = context.tt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: tt.iconSize,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
        SizedBox(width: tt.rowGap),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
