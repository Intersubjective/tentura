import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../bloc/beacon_create_cubit.dart';
import '../dialog/beacon_publish_dialog.dart';
import '../widget/image_tab.dart';
import '../widget/info_tab.dart';
import '../widget/polling_tab.dart';

@RoutePage()
class BeaconCreateScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconCreateScreen({
    @QueryParam(kQueryBeaconDraftId) this.draftId = '',
    @QueryParam(kQueryBeaconEditId) this.editId = '',
    super.key,
  });

  /// Server draft beacon id when opening from My Work / deep link.
  final String draftId;

  /// Server open beacon id when editing a published beacon.
  final String editId;

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
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ContextCubit, ContextState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<BeaconCreateCubit, BeaconCreateState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );
}

class _BeaconCreateScreenState extends State<BeaconCreateScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final _tabController = TabController(length: 3, vsync: this);

  late final _beaconCreateCubit = context.read<BeaconCreateCubit>();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const AutoLeadingButton(),
        title: BlocSelector<BeaconCreateCubit, BeaconCreateState,
            ({bool isDraft, bool isEdit})>(
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
                return Padding(
                  padding: kPaddingH,
                  child: TextButton(
                    key: const Key('BeaconEdit.SaveChangesButton'),
                    onPressed: state.isLoading
                        ? null
                        : () async {
                            await _beaconCreateCubit.saveEdit(
                              context: context
                                  .read<ContextCubit>()
                                  .state
                                  .selected,
                            );
                          },
                    child: Text(l10n.buttonSaveChanges),
                  ),
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: kPaddingH,
                    child: BlocSelector<BeaconCreateCubit, BeaconCreateState,
                        bool>(
                      key: const Key('BeaconCreate.SaveDraftButton'),
                      bloc: _beaconCreateCubit,
                      selector: (s) => s.isLoading,
                      builder: (context, isLoading) => TextButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                await _beaconCreateCubit.saveDraft(
                                  context: context
                                      .read<ContextCubit>()
                                      .state
                                      .selected,
                                );
                              },
                        child: Text(l10n.buttonSaveDraft),
                      ),
                    ),
                  ),
                  Padding(
                    padding: kPaddingH,
                    child: BlocSelector<BeaconCreateCubit, BeaconCreateState,
                        bool>(
                      key: const Key('BeaconCreate.PublishButton'),
                      bloc: _beaconCreateCubit,
                      selector: (s) => s.canTryToPublish,
                      builder: (context, canTryToPublish) => TextButton(
                        onPressed: canTryToPublish
                            ? () async {
                                if (await BeaconPublishDialog.show(context) ??
                                    false) {
                                  if (context.mounted) {
                                    await _beaconCreateCubit.publish(
                                      context: context
                                          .read<ContextCubit>()
                                          .state
                                          .selected,
                                    );
                                  }
                                }
                              }
                            : null,
                        child: Text(l10n.buttonPublish),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
                key: const Key('BeaconCreate.LoadIndicator'),
                bloc: _beaconCreateCubit,
                selector: (state) => state.isLoading,
                builder: LinearPiActive.builder,
              ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.beaconInfo),
                  Tab(text: l10n.beaconImage),
                  Tab(text: l10n.pollSectionTitle),
                ],
              ),
            ],
          ),
        ),
      ),
      body: BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
        bloc: _beaconCreateCubit,
        buildWhen: (p, c) =>
            p.status != c.status ||
            p.draftId != c.draftId ||
            p.title != c.title,
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
            child: Padding(
              padding: kPaddingH + kPaddingLargeT,
              child: BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
                key: const Key('BeaconCreate.FormBody'),
                bloc: _beaconCreateCubit,
                selector: (state) => state.isLoading,
                builder: (context, isLoading) => AbsorbPointer(
                  absorbing: isLoading,
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      InfoTab(),
                      ImageTab(),
                      PollingTab(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
