import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

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
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: scheme.surfaceContainer,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: tt.appBarHeight,
        foregroundColor: scheme.onSurface,
        leading: BackButton(
          onPressed: () => context.router.maybePop(),
        ),
        title: Text(
          l10n.inboxRejectedTitle,
          style: TenturaText.title(scheme.onSurface),
        ),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaContentColumn(
          child: BlocBuilder<NewStuffCubit, NewStuffState>(
          buildWhen: (p, c) =>
              p.inboxLastSeenMs != c.inboxLastSeenMs ||
              p.maxInboxActivityMs != c.maxInboxActivityMs,
          builder: (context, _) {
            final newStuff = context.read<NewStuffCubit>();
            return BlocBuilder<InboxCubit, InboxState>(
              buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
              builder: (_, state) {
                if (state.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                if (state.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: tt.iconSize * 2,
                          color: scheme.error,
                        ),
                        SizedBox(height: tt.sectionGap),
                        FilledButton(
                          onPressed: () => unawaited(inboxCubit.fetch()),
                          child: Text(l10n.myWorkRetry),
                        ),
                      ],
                    ),
                  );
                }
                final items = state.rejected;
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: tt.cardPadding,
                      child: Text(
                        l10n.inboxTabRejectedEmpty,
                        style: TenturaText.bodyMedium(scheme.onSurfaceVariant),
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
                    separatorBuilder: (_, _) =>
                        SizedBox(height: tt.rowGap),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return InboxItemTile(
                        key: ValueKey(item.beaconId),
                        item: item,
                        inboxHighlight: newStuff.inboxRowHighlight(
                          latestForwardAt: item.latestForwardAt,
                          forwardCount: item.forwardCount,
                          beaconActivityEpochMs:
                              item.newStuffBeaconOnlyActivityEpochMs,
                        ),
                        onOpenBeacon: () => context.router.pushPath(
                          '$kPathBeaconView/${item.beaconId}?$kQueryBeaconEntry=$kBeaconEntryInbox',
                        ),
                        onTap: () => context.router.pushPath(
                          '$kPathForwardBeacon/${item.beaconId}',
                        ),
                        onMoveToInbox: () => inboxCubit.unreject(item.beaconId),
                        showCtaRow: false,
                        showProvenance: false,
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        ),
      ),
    );
  }
}
