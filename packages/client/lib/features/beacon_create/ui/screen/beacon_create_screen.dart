import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../bloc/beacon_create_cubit.dart';
import '../dialog/beacon_send_confirmation_dialog.dart';
import '../widget/info_tab.dart';
import '../widget/recipients_tab.dart';

/// After a successful [BeaconCreateCubit.makeLive], leave create and open the
/// published request. Shared so widget tests can assert [StackRouter.popAndPush]
/// without pumping the full create form.
@visibleForTesting
Future<void> popCreateAndOpenLiveBeacon(
  StackRouter router, {
  required String beaconId,
}) => router.popAndPush(BeaconViewRoute(id: beaconId));

@RoutePage()
class BeaconCreateScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconCreateScreen({
    @QueryParam(kQueryBeaconDraftId) this.draftId = '',
    @QueryParam(kQueryBeaconEditId) this.editId = '',
    @QueryParam(kQueryBeaconCreateTab) this.initialTab = '',
    @QueryParam(kQueryBeaconForwardTo) this.forwardToUserId = '',
    super.key,
  });

  /// Server draft beacon id when opening from My Work / deep link.
  final String draftId;

  /// Server open beacon id when editing a published beacon.
  final String editId;

  /// Optional initial focus: [kBeaconCreateTabRecipients] or
  /// [kBeaconCreateTabImage] (Cover editor on the form step).
  final String initialTab;

  /// Optional profile-route recipient to preselect when Recipients is prepared.
  final String forwardToUserId;

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
        ),
      ),
    ],
    child: this,
  );
}

class _BeaconCreateScreenState extends State<BeaconCreateScreen> {
  static const _formStep = 0;
  static const _recipientsStep = 1;

  final _formKey = GlobalKey<FormState>();

  late final _beaconCreateCubit = context.read<BeaconCreateCubit>();

  late int _step = widget.initialTab == kBeaconCreateTabRecipients
      ? _recipientsStep
      : _formStep;

  ForwardCubit? _forwardCubit;
  String? _forwardCubitDraftId;
  bool _recipientsDraftEnsuring = false;

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
    if (_beaconCreateCubit.state.draftId != null) {
      return;
    }
    _recipientsDraftEnsuring = true;
    final contextName = context.read<ContextCubit>().state.selected;
    await _beaconCreateCubit.ensureDraft(
      context: contextName,
      showMessage: false,
    );
    if (mounted) {
      setState(() => _recipientsDraftEnsuring = false);
    }
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
            ? const <String>{}
            : {widget.forwardToUserId},
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
    await popCreateAndOpenLiveBeacon(context.router, beaconId: id);
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
      await context.router.maybePop();
    }
  }

  Future<void> _leaveForm() async {
    _formKey.currentState?.save();
    await _beaconCreateCubit.flushAutosave();
    if (!mounted) return;
    if (context.router.canPop()) {
      await context.router.maybePop();
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
      if ((confirmed ?? false) && mounted) {
        await _beaconCreateCubit.deleteDraft();
      }
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
        await _leaveForm();
      },
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          centerTitle: true,
          leading: isRecipients
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step = _formStep),
                )
              : AutoLeadingWithFallback(
                  fallbackPath: kPathMyWork,
                  closeWhenCanPop: true,
                  onPressed: () => unawaited(_leaveForm()),
                ),
          trailingIsIcon: false,
          title:
              BlocSelector<
                BeaconCreateCubit,
                BeaconCreateState,
                ({bool isDraft, bool isEdit, bool isLive})
              >(
                bloc: _beaconCreateCubit,
                selector: (s) => (
                  isDraft: s.draftId != null,
                  isEdit: s.isEditMode,
                  isLive: s.isLive,
                ),
                builder: (context, mode) => Text(
                  mode.isEdit
                      ? l10n.editBeaconTitle
                      : mode.isLive
                      ? l10n.liveRequestTitle
                      : mode.isDraft
                      ? l10n.editDraftTitle
                      : l10n.createNewBeacon,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
          actions: [
            if (!isRecipients)
              BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
                bloc: _beaconCreateCubit,
                buildWhen: (p, c) =>
                    p.isEditMode != c.isEditMode ||
                    p.isLive != c.isLive ||
                    p.draftId != c.draftId,
                builder: (context, state) {
                  if (state.isEditMode || state.isLive) {
                    return const SizedBox.shrink();
                  }
                  return TenturaTextAction(
                    label: l10n.beaconCreateDraftAction,
                    tone: TenturaTone.neutral,
                    onPressed: () async {
                      final box = context.findRenderObject() as RenderBox?;
                      final overlay =
                          Overlay.of(context).context.findRenderObject()
                              as RenderBox?;
                      if (box == null || overlay == null) return;
                      final position = RelativeRect.fromRect(
                        Rect.fromPoints(
                          box.localToGlobal(Offset.zero, ancestor: overlay),
                          box.localToGlobal(
                            box.size.bottomRight(Offset.zero),
                            ancestor: overlay,
                          ),
                        ),
                        Offset.zero & overlay.size,
                      );
                      final selected = await showMenu<String>(
                        context: context,
                        position: position,
                        items: [
                          PopupMenuItem(
                            value: 'save',
                            child: Text(l10n.buttonSaveDraft),
                          ),
                          if (state.draftId != null)
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(l10n.deleteBeacon),
                            ),
                        ],
                      );
                      if (selected != null && context.mounted) {
                        await _onDraftMenu(selected);
                      }
                    },
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
                if (state.isEditMode) return;
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
                    p.isEditMode != c.isEditMode,
                builder: (context, state) {
                  if (state.isEditMode && _step != _formStep) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _step != _formStep) {
                        setState(() => _step = _formStep);
                      }
                    });
                  }
                  if ((widget.draftId.isNotEmpty && state.draftId == null ||
                          widget.editId.isNotEmpty && state.editId == null) &&
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
      child: SafeArea(
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
                    child: Text(l10n.buttonSaveChanges),
                  ),
                );
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
                        if (!state.isLive)
                          Expanded(
                            child: SizedBox(
                              height: tt.buttonHeight,
                              child: OutlinedButton(
                                key: TestIds.key(TestIds.requestMakeLive),
                                onPressed: state.isLoading ||
                                        !state.canTryToPublish
                                    ? null
                                    : () => unawaited(_makeLive()),
                                child: Text(l10n.buttonMakeLive),
                              ),
                            ),
                          ),
                        if (!state.isLive) SizedBox(width: tt.rowGap),
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
                                child: Text(l10n.buttonSaveChanges),
                              ),
                            ),
                          ),
                      ],
                    ),
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
                        child: Text(l10n.buttonSaveChanges),
                      ),
                    )
                  else
                    Opacity(
                      opacity: valid ? 1 : 0.4,
                      child: SizedBox(
                        height: tt.buttonHeight,
                        width: double.infinity,
                        child: FilledButton(
                          key: TestIds.key(TestIds.requestRecipientsTab),
                          onPressed: state.isLoading
                              ? null
                              : () => unawaited(_onNext()),
                          child: Text(l10n.beaconCreateNextRecipients),
                        ),
                      ),
                    ),
                  if (!state.isLive) ...[
                    SizedBox(height: tt.tightGap),
                    if (state.isAutosaving)
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
                        onPressed: () =>
                            unawaited(_openRecipientsStep()),
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
