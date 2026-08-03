import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/blocked_users_cubit.dart';
import '../widget/blocked_user_tile.dart';

@RoutePage()
class BlockedUsersScreen extends StatelessWidget implements AutoRouteWrapper {
  const BlockedUsersScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = GetIt.I<BlockedUsersCubit>();
      unawaited(cubit.fetch());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.blockedUsersTitle),
      ),
      body: SafeArea(
        child: const BlockedUsersBody(),
      ),
    );
  }
}

/// Scrollable blocked-users list body (extracted for responsive layout tests).
@visibleForTesting
class BlockedUsersBody extends StatelessWidget {
  const BlockedUsersBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<BlockedUsersCubit, BlockedUsersState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.blocks.isEmpty) {
          return TenturaContentColumn(
            child: Center(
              child: Text(
                l10n.blockedUsersEmpty,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return TenturaContentColumn(
          child: ListView.builder(
            itemCount: state.blocks.length,
            itemBuilder: (context, index) {
              final intent = state.blocks[index];
              return _BlockedListEntry(
                intent: intent,
                state: state,
              );
            },
          ),
        );
      },
    );
  }
}

class _BlockedListEntry extends StatelessWidget {
  const _BlockedListEntry({
    required this.intent,
    required this.state,
  });

  final BlockIntent intent;
  final BlockedUsersState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<BlockedUsersCubit>();
    final originId = intent.id;
    final isExpanded = state.expandedOriginId == originId;
    final canExpand = intent.inheritedCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlockedUserTile(
          intent: intent,
          onUnblock: () => cubit.unblock(originId),
          onTap: canExpand
              ? () {
                  if (isExpanded) {
                    cubit.collapseInherited();
                  } else {
                    unawaited(cubit.expandInherited(originId));
                  }
                }
              : null,
        ),
        if (intent.cascadePending)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: context.tt.rowGap,
              children: [
                const LinearProgressIndicator(),
                Text(
                  l10n.blockedInheritedPending,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (isExpanded) ...[
          if (state.expandedLoading)
            Padding(
              padding: EdgeInsets.all(context.tt.rowGap),
              child: const Center(child: CircularProgressIndicator()),
            )
          else
            for (final profile in state.expandedInherited)
              _InheritedBlockRow(
                profile: profile,
                originId: originId,
              ),
        ],
      ],
    );
  }
}

class _InheritedBlockRow extends StatelessWidget {
  const _InheritedBlockRow({
    required this.profile,
    required this.originId,
  });

  final Profile profile;
  final String originId;

  Future<void> _confirmUnhide(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.blockUnhideOriginTitle,
      content: l10n.blockUnhideOriginWarning,
      confirmLabel: l10n.blockUnhideOne,
      cancelLabel: l10n.buttonCancel,
    );
    if ((confirmed ?? false) && context.mounted) {
      await context.read<BlockedUsersCubit>().unhideOrigin(originId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<BlockedUsersCubit>();
    final tt = context.tt;

    return ListTile(
      contentPadding: EdgeInsets.only(
        left: tt.screenHPadding * 2,
        right: tt.screenHPadding,
      ),
      leading: TenturaAvatar.medium(profile: profile),
      title: Text(profile.shownName),
      trailing: Wrap(
        spacing: tt.rowGap,
        children: [
          TenturaTextAction(
            label: l10n.blockUnhideOne,
            onPressed: () => unawaited(_confirmUnhide(context)),
          ),
          TenturaTextAction(
            label: l10n.blockPromoteToDirect,
            onPressed: () => cubit.promoteToDirect(profile.id),
          ),
        ],
      ),
    );
  }
}
