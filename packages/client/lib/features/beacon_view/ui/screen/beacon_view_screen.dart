import 'package:nil/nil.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/widget/author_info.dart';

import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/beacon_view_cubit.dart';
import '../widget/beacon_mine_control.dart';

@RoutePage()
class BeaconViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  @override
  Widget wrappedRoute(_) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ScreenCubit(),
      ),
      BlocProvider(
        create: (_) => BeaconViewCubit(
          myProfile: GetIt.I<ProfileCubit>().state.profile,
          id: id,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<BeaconViewCubit, BeaconViewState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.beaconViewTitle),
        leading: isDeepLink == 'true'
            ? BackButton(
                onPressed: () => AutoRouter.of(context).navigatePath(kPathHome),
              )
            : const AutoLeadingButton(),
        actions: [
          BlocSelector<BeaconViewCubit, BeaconViewState, bool>(
            selector: (state) => state.isBeaconMine,
            builder: (_, isBeaconMine) => isBeaconMine
                ? nil
                : PopupMenuButton(
                    itemBuilder: (_) => <PopupMenuEntry<void>>[
                      PopupMenuItem(
                        onTap: () => screenCubit.showComplaint(id),
                        child: Text(l10n.buttonComplaint),
                      ),
                    ],
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<BeaconViewCubit, BeaconViewState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: beaconViewCubit,
          ),
        ),
      ),
      body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
        bloc: beaconViewCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          final beacon = state.beacon;
          return ListView(
            padding: kPaddingAll,
            children: [
              // Author
              if (state.isBeaconNotMine)
                AuthorInfo(
                  author: beacon.author,
                  key: ValueKey(beacon.author),
                ),

              // Beacon Info (overview)
              BeaconInfo(
                key: ValueKey(beacon),
                beacon: beacon,
                isTitleLarge: true,
                isShowMoreEnabled: false,
                isShowBeaconEnabled: false,
              ),

              // Beacon owner controls
              if (state.isBeaconMine)
                Padding(
                  padding: kPaddingSmallV,
                  child: BeaconMineControl(key: ValueKey(beacon.id)),
                ),

              const SizedBox(height: kSpacingMedium),

              // Primary actions for non-owners
              if (state.isBeaconNotMine)
                Padding(
                  padding: kPaddingSmallV,
                  child: Row(
                    children: [
                      Expanded(
                        child: BlocSelector<BeaconViewCubit, BeaconViewState,
                            bool>(
                          selector: (s) => s.isCommitted,
                          builder: (_, isCommitted) => isCommitted
                              ? OutlinedButton.icon(
                                  onPressed: beaconViewCubit.withdraw,
                                  icon: const Icon(Icons.check_circle),
                                  label: Text(l10n.labelCommitted),
                                )
                              : FilledButton.icon(
                                  onPressed: () =>
                                      beaconViewCubit.commit(),
                                  icon: const Icon(Icons.handshake),
                                  label: Text(l10n.labelCommit),
                                ),
                        ),
                      ),
                      const SizedBox(width: kSpacingSmall),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.router.pushPath(
                            '$kPathForwardBeacon/${beacon.id}',
                          ),
                          icon: const Icon(Icons.send),
                          label: Text(l10n.labelForward),
                        ),
                      ),
                    ],
                  ),
                ),

              // Forward button for owners
              if (state.isBeaconMine)
                Padding(
                  padding: kPaddingSmallV,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.router.pushPath(
                        '$kPathForwardBeacon/${beacon.id}',
                      ),
                      icon: const Icon(Icons.send),
                      label: Text(l10n.labelForward),
                    ),
                  ),
                ),

              const Divider(height: kSpacingLarge),

              // Timeline section
              Text(
                l10n.labelTimeline,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingSmall),

              if (state.timeline.isEmpty)
                Padding(
                  padding: kPaddingSmallV,
                  child: Text(
                    l10n.noActivityYet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              for (final entry in state.timeline)
                _TimelineEntryTile(entry: entry),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingSmallV,
      child: switch (entry) {
        final TimelineForward e => Row(
            children: [
              Icon(
                Icons.forward_to_inbox,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  l10n.timelineForwarded(
                    e.edge.sender.title,
                    e.edge.recipient.title,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                dateFormatYMD(e.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        final TimelineCommitment e => Row(
            children: [
              Icon(
                Icons.handshake,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  e.message.isNotEmpty
                      ? l10n.timelineCommittedWithMessage(
                          e.user.title,
                          e.message,
                        )
                      : l10n.timelineCommitted(e.user.title),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                dateFormatYMD(e.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        final TimelineUpdate e => Row(
            children: [
              Icon(
                Icons.edit_note,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  l10n.timelineUpdate(e.author.title, e.content),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                dateFormatYMD(e.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
      },
    );
  }
}
