import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/inbox_cubit.dart';
import '../widget/inbox_item_tile.dart';

@RoutePage()
class InboxRejectedScreen extends StatelessWidget implements AutoRouteWrapper {
  const InboxRejectedScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, accountId) => BlocProvider(
          key: ValueKey(accountId),
          create: (_) {
            final cubit = InboxCubit(userId: accountId);
            unawaited(cubit.fetch());
            return cubit;
          },
          child: this,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final inboxCubit = context.read<InboxCubit>();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.inboxRejectedTitle),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaContentColumn(
          child: BlocBuilder<InboxCubit, InboxState>(
            buildWhen: (_, c) => c.isSuccess || c.isLoading,
            builder: (_, state) {
              if (state.isLoading) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              final items = state.rejected;
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: tt.cardPadding,
                    child: Text(
                      l10n.inboxTabRejectedEmpty,
                      style: TenturaText.bodyMedium(
                        scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: inboxCubit.fetch,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return InboxItemTile(
                      key: ValueKey(item.beaconId),
                      item: item,
                      onOpenBeacon: () => context.router.push(
                        BeaconViewRoute(
                          id: item.beaconId,
                          entry: kBeaconEntryInbox,
                        ),
                      ),
                      onTap: () => context.router.push(
                        ForwardBeaconRoute(beaconId: item.beaconId),
                      ),
                      onMoveToInbox: () => inboxCubit.unreject(item.beaconId),
                      showCtaRow: false,
                      showProvenance: false,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
