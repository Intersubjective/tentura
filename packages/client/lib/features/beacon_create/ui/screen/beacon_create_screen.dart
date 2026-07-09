import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';
import '../dialog/beacon_send_confirmation_dialog.dart';
import '../widget/image_tab.dart';
import '../widget/info_tab.dart';
import '../widget/recipients_tab.dart';

String? _publishBlockedDetail(L10n l10n, BeaconPublishBlocker blocker) =>
    switch (blocker) {
      BeaconPublishBlocker.title => l10n.beaconPublishBlockedTitle,
      BeaconPublishBlocker.description => l10n.beaconPublishBlockedDescription,
    };

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

  /// Optional initial tab (`recipients` opens the Recipients tab).
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

class _BeaconCreateScreenState extends State<BeaconCreateScreen>
    with TickerProviderStateMixin {
  static const _recipientsTabIndex = 2;

  final _formKey = GlobalKey<FormState>();

  late final _tabController = TabController(length: 3, vsync: this);

  late final _beaconCreateCubit = context.read<BeaconCreateCubit>();

  ForwardCubit? _forwardCubit;
  String? _forwardCubitDraftId;
  bool _recipientsDraftEnsuring = false;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);
    if (widget.initialTab == kBeaconCreateTabRecipients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openRecipientsTab());
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    unawaited(_forwardCubit?.close());
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging &&
        _tabController.index == _recipientsTabIndex) {
      unawaited(_prepareRecipientsTab());
    }
  }

  Future<void> _openRecipientsTab() async {
    if (!mounted || _beaconCreateCubit.state.isEditMode) return;
    await _prepareRecipientsTab();
    if (mounted) {
      _tabController.animateTo(_recipientsTabIndex);
    }
  }

  Future<void> _prepareRecipientsTab() async {
    if (_beaconCreateCubit.state.isEditMode || _recipientsDraftEnsuring) {
      return;
    }
    // Don't attempt server draft creation until required fields are present.
    // This tab should be reachable without triggering a validation snackbar.
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

  Future<void> _sendRequest() async {
    final contextName = context.read<ContextCubit>().state.selected;
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final contextName = context.watch<ContextCubit>().state.selected;
    final actionButtonStyle = TextButton.styleFrom(
      minimumSize: Size(0, tt.buttonHeight),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        centerTitle: true,
        leading: const AutoLeadingButton(),
        trailingIsIcon: false,
        title:
            BlocSelector<
              BeaconCreateCubit,
              BeaconCreateState,
              ({bool isDraft, bool isEdit})
            >(
              bloc: _beaconCreateCubit,
              selector: (s) =>
                  (isDraft: s.draftId != null, isEdit: s.isEditMode),
              builder: (context, mode) => Text(
                mode.isEdit
                    ? l10n.editBeaconTitle
                    : mode.isDraft
                    ? l10n.editDraftTitle
                    : l10n.createNewBeacon,
              ),
            ),
        actions: [
          BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
            bloc: _beaconCreateCubit,
            buildWhen: (p, c) =>
                p.isEditMode != c.isEditMode || p.isLoading != c.isLoading,
            builder: (context, state) {
              if (state.isEditMode) {
                return Tooltip(
                  message: l10n.buttonSaveChanges,
                  child: TextButton(
                    key: const Key('BeaconEdit.SaveChangesButton'),
                    style: actionButtonStyle,
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
              return BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
                key: const Key('BeaconCreate.SaveDraftButton'),
                bloc: _beaconCreateCubit,
                selector: (s) => s.isLoading,
                builder: (context, isLoading) => Tooltip(
                  message: l10n.buttonSaveDraft,
                  child: TextButton(
                    style: actionButtonStyle,
                    onPressed: isLoading
                        ? null
                        : () async {
                            await _beaconCreateCubit.saveDraft(
                              context: contextName,
                            );
                          },
                    child: Text(l10n.buttonSaveDraft),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.beaconInfo),
            Tab(text: l10n.beaconImage),
            Tab(text: l10n.beaconRecipients),
          ],
        ),
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: BlocListener<BeaconCreateCubit, BeaconCreateState>(
            bloc: _beaconCreateCubit,
            listenWhen: (p, c) =>
                p.publishBlocker != c.publishBlocker || p.draftId != c.draftId,
            listener: (context, state) {
              if (!mounted) return;
              if (_tabController.index != _recipientsTabIndex) return;
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
                if ((widget.draftId.isNotEmpty && state.draftId == null ||
                        widget.editId.isNotEmpty && state.editId == null) &&
                    state.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                return Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: () => _beaconCreateCubit.validate(
                    _formKey.currentState?.validate() ?? false,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BlocSelector<
                        BeaconCreateCubit,
                        BeaconCreateState,
                        ({bool show, BeaconPublishBlocker? blocker})
                      >(
                        bloc: _beaconCreateCubit,
                        selector: (s) => (
                          show:
                              !s.isEditMode &&
                              !s.canTryToPublish &&
                              !s.isLoading,
                          blocker: s.publishBlocker,
                        ),
                        builder: (context, hint) {
                          if (!hint.show || hint.blocker == null) {
                            return const SizedBox.shrink();
                          }
                          final scheme = Theme.of(context).colorScheme;
                          return Padding(
                            padding: EdgeInsets.only(bottom: tt.rowGap),
                            child: Material(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(tt.cardRadius),
                              child: Padding(
                                padding: EdgeInsets.all(tt.cardPadding.top),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: tt.iconSize,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    SizedBox(width: tt.tightGap * 2),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.beaconPublishBlockedHint,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          SizedBox(height: tt.tightGap),
                                          Text(
                                            _publishBlockedDetail(
                                                  l10n,
                                                  hint.blocker!,
                                                ) ??
                                                '',
                                            style: TenturaText.bodySmall(
                                              scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            tt.screenHPadding,
                            tt.sectionGap * 2,
                            tt.screenHPadding,
                            0,
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
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      const InfoTab(
                                        key: ValueKey('BeaconCreate.InfoTab'),
                                      ),
                                      const ImageTab(),
                                      _buildRecipientsTab(state, contextName),
                                    ],
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
