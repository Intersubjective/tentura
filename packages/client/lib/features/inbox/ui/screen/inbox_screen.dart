import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

import '../bloc/inbox_cubit.dart';
import '../widget/inbox_item_tile.dart';

@RoutePage()
class InboxScreen extends StatelessWidget implements AutoRouteWrapper {
  const InboxScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, _) => BlocProvider(
          create: (_) => InboxCubit(
            initialContext: context.read<ContextCubit>().state.selected,
          ),
          child: MultiBlocListener(
            listeners: [
              BlocListener<ContextCubit, ContextState>(
                listenWhen: (p, c) => p.selected != c.selected,
                listener: (context, state) =>
                    context.read<InboxCubit>().fetch(state.selected),
              ),
              const BlocListener<InboxCubit, InboxState>(
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
    final inboxCubit = context.read<InboxCubit>();
    return SafeArea(
      minimum: kPaddingSmallH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ContextDropDown(),
          Expanded(
            child: BlocBuilder<InboxCubit, InboxState>(
              buildWhen: (_, c) => c.isSuccess || c.isLoading,
              builder: (_, state) {
                if (state.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                if (state.items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: kSpacingMedium),
                        Text(
                          l10n.inboxEmpty,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          l10n.inboxEmptyHint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final needsMe = state.needsMe;
                final watching = state.watching;
                return RefreshIndicator.adaptive(
                  onRefresh: () => Future.wait([
                    inboxCubit.fetch(),
                    context.read<ContextCubit>().fetch(fromCache: false),
                  ]),
                  child: ListView(
                    children: [
                      if (needsMe.isNotEmpty) ...[
                        Padding(
                          padding: kPaddingSmallV,
                          child: Text(
                            l10n.inboxNeedsMe,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        for (final item in needsMe)
                          Padding(
                            padding: kPaddingSmallV,
                            child: InboxItemTile(
                              key: ValueKey(item.beaconId),
                              item: item,
                              onTap: () => context.router.pushPath(
                                '$kPathBeaconView/${item.beaconId}',
                              ),
                              onHide: () => inboxCubit.hide(item.beaconId),
                              onToggleWatch: () =>
                                  inboxCubit.toggleWatching(item.beaconId),
                            ),
                          ),
                      ],
                      if (watching.isNotEmpty) ...[
                        Padding(
                          padding: kPaddingSmallV,
                          child: Text(
                            l10n.inboxWatching,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                        for (final item in watching)
                          Padding(
                            padding: kPaddingSmallV,
                            child: InboxItemTile(
                              key: ValueKey(item.beaconId),
                              item: item,
                              onTap: () => context.router.pushPath(
                                '$kPathBeaconView/${item.beaconId}',
                              ),
                              onHide: () => inboxCubit.hide(item.beaconId),
                              onToggleWatch: () =>
                                  inboxCubit.toggleWatching(item.beaconId),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
