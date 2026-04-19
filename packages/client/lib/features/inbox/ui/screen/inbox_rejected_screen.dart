import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

import '../bloc/inbox_cubit.dart';
import '../message/inbox_messages.dart';
import '../widget/inbox_item_tile.dart';

@RoutePage()
class InboxRejectedScreen extends StatelessWidget implements AutoRouteWrapper {
  const InboxRejectedScreen({super.key});

  static const _listPadding = EdgeInsets.fromLTRB(8, 4, 8, 12);
  static const _separatorH = 6.0;

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
          child: BlocListener<InboxCubit, InboxState>(
            listener: (context, state) {
              final s = state.status;
              if (s is StateIsMessaging &&
                  s.message is InboxBeaconMovedMessage) {
                return;
              }
              commonScreenBlocListener(context, state);
            },
            child: this,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inboxCubit = context.read<InboxCubit>();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        foregroundColor: scheme.onSurface,
        leading: BackButton(
          onPressed: () => context.router.maybePop(),
        ),
        title: Text(l10n.inboxRejectedTitle),
      ),
      body: BlocBuilder<NewStuffCubit, NewStuffState>(
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
              final items = state.rejected;
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.inboxTabRejectedEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
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
                  padding: _listPadding,
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _separatorH),
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
                        '$kPathBeaconView/${item.beaconId}',
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
    );
  }
}
