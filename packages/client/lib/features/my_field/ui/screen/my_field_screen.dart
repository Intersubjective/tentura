import 'package:nil/nil.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_tile.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

import '../bloc/my_field_cubit.dart';
import '../dialog/my_field_choose_tags_dialog.dart';

@RoutePage()
class MyFieldScreen extends StatelessWidget implements AutoRouteWrapper {
  const MyFieldScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, _) => BlocProvider(
          create: (_) => MyFieldCubit(
            initialContext: context.read<ContextCubit>().state.selected,
          ),
          child: MultiBlocListener(
            listeners: [
              BlocListener<ContextCubit, ContextState>(
                listenWhen: (p, c) => p.selected != c.selected,
                listener: (context, state) =>
                    context.read<MyFieldCubit>().fetch(state.selected),
              ),
              const BlocListener<MyFieldCubit, MyFieldState>(
                listener: commonScreenBlocListener,
              ),
            ],
            child: this,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final myFieldCubit = context.read<MyFieldCubit>();
    return SafeArea(
      minimum: kPaddingSmallH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Context selector
          const ContextDropDown(),

          // Tags cloud
          BlocSelector<MyFieldCubit, MyFieldState, List<String>>(
            selector: (state) => state.selectedTags,
            builder: (_, selectedTags) => Wrap(
              spacing: kSpacingSmall,
              children: [
                ActionChip(
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  avatar: const Icon(Icons.local_offer_outlined),
                  label: AnimatedSwitcher(
                    duration: kFastAnimationDuration,
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      axis: Axis.horizontal,
                      child: child,
                    ),
                    child: selectedTags.isEmpty
                        ? Text(
                            l10n.filterByTag,
                            key: ValueKey(selectedTags),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          )
                        : const Nil(),
                  ),
                  onPressed: () async {
                    final selected = await MyFieldChooseTagsDialog.show(
                      context,
                      allTags: myFieldCubit.state.tags,
                      selectedTags: myFieldCubit.state.selectedTags,
                    );

                    if (selected != null) {
                      myFieldCubit.setSelectedTags(selected);
                    }
                  },
                ),
                for (final tag in selectedTags)
                  Chip(
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    label: Text(
                      '#$tag',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    onDeleted: () => myFieldCubit.removeTag(tag),
                  ),
              ],
            ),
          ),

          // Beacons list
          Expanded(
            child: BlocBuilder<MyFieldCubit, MyFieldState>(
              bloc: myFieldCubit,
              buildWhen: (_, c) => c.isSuccess || c.isLoading,
              builder: (_, state) => state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator.adaptive(),
                    )
                  : RefreshIndicator.adaptive(
                      onRefresh: () => Future.wait([
                        myFieldCubit.fetch(),
                        context.read<ContextCubit>().fetch(fromCache: false),
                      ]),
                      child: ListView.builder(
                        itemCount: state.visibleBeacons.length,
                        itemBuilder: (_, i) {
                          final beacon = state.visibleBeacons[i];
                          return Padding(
                            padding: kPaddingSmallV,
                            child: BeaconTile(
                              key: ValueKey(beacon),
                              onClickTag: myFieldCubit.addTag,
                              beacon: beacon,
                              isMine: false,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
