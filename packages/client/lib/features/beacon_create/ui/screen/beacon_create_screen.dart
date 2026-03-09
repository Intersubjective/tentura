import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

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
  const BeaconCreateScreen({super.key});

  @override
  State<BeaconCreateScreen> createState() => _BeaconCreateScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ContextCubit(),
      ),
      BlocProvider(
        create: (_) => BeaconCreateCubit(),
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

  late final _l10n = L10n.of(context)!;
  late final _tabController = TabController(length: 3, vsync: this);
  late final _beaconCreateCubit = context.read<BeaconCreateCubit>();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      leading: const AutoLeadingButton(),
      title: Text(_l10n.createNewBeacon),
      actions: [
        // Publish Button
        Padding(
          padding: kPaddingH,
          child: BlocSelector<BeaconCreateCubit, BeaconCreateState, bool>(
            key: const Key('BeaconCreate.PublishButton'),
            bloc: _beaconCreateCubit,
            selector: (state) => state.canTryToPublish,
            builder: (context, canTryToPublish) => TextButton(
              onPressed: canTryToPublish
                  ? () async {
                      if (await BeaconPublishDialog.show(context) ?? false) {
                        // Publish confirmed
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
              child: Text(_l10n.buttonPublish),
            ),
          ),
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
                Tab(text: _l10n.beaconInfo),
                Tab(text: _l10n.beaconImage),
                Tab(text: _l10n.pollSectionTitle),
              ],
            ),
          ],
        ),
      ),
    ),

    body: Form(
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
    ),
  );
}
