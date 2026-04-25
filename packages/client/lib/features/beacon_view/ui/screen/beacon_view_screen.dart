import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_author_subline.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/commitment_message_dialog.dart';
import '../widget/activity_list.dart';
import '../widget/beacon_operational_collapsible_header.dart';
import '../widget/beacon_primary_cta_bar.dart';
import '../widget/commitment_tile.dart';
import '../widget/coordination_response_bottom_sheet.dart';
import '../widget/overview/beacon_overview_tab.dart';

/// Query [kQueryBeaconViewTab]: `overview` | `commitments` | `activity` (legacy: `timeline`, `details`, `forwards`).
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'commitments':
      return 1;
    case 'activity':
    case 'timeline':
      return 2;
    case 'details':
    case 'forwards':
    case 'overview':
    default:
      return 0;
  }
}

bool _forwardInPrimaryCta(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isCommitted && b.allowsNewCommitAsNonAuthor) {
    return true;
  }
  if (state.isCommitted && !b.allowsWithdrawWhileCommitted) {
    return true;
  }
  return false;
}

bool _hideCommitWithdrawFromOverflow(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isCommitted && b.allowsNewCommitAsNonAuthor) {
    return true;
  }
  if (state.isCommitted && b.allowsWithdrawWhileCommitted) {
    return true;
  }
  return false;
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;

Widget _beaconViewAppBarOverflow({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
}) {
  final b = state.beacon;
  final beaconId = b.id;
  final hideOverflowForward = _forwardInPrimaryCta(state);
  final hideCommitWithdraw = _hideCommitWithdrawFromOverflow(state);

  if (state.isBeaconMine) {
    return BeaconOverflowMenu(
      beacon: b,
      onGraph: b.myVote >= 0 ? () => screenCubit.showGraphFor(beaconId) : null,
      onShare: () => unawaited(
        ShareCodeDialog.show(
          context,
          link: Uri.parse(kServerName).replace(
            queryParameters: {'id': beaconId},
            path: kPathAppLinkView,
          ),
          header: beaconId,
        ),
      ),
      onToggleLifecycle: () async {
        if (!context.mounted) return;
        if (state.beacon.isListed) {
          if (await BeaconCloseConfirmDialog.show(context) != true) {
            return;
          }
          if (!context.mounted) return;
        }
        await cubit.toggleLifecycle();
      },
      onEdit: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              context.router.pushPath(
                '$kPathBeaconNew?$kQueryBeaconEditId=$beaconId',
              ),
            )
          : null,
      onForward: () => unawaited(
        context.router.pushPath('$kPathForwardBeacon/$beaconId'),
      ),
      onViewForwards: () => unawaited(
        context.router.pushPath('$kPathBeaconForwards/$beaconId'),
      ),
      onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
      onDelete: () async {
        if (!context.mounted) return;
        if (await BeaconDeleteDialog.show(context) ?? false) {
          if (!context.mounted) return;
          await cubit.delete(beaconId);
        }
      },
    );
  }

  return BeaconOverflowMenu(
    beacon: b,
    onCommit:
        !hideCommitWithdraw &&
            !state.isCommitted &&
            b.allowsNewCommitAsNonAuthor
        ? () async {
            if (!context.mounted) return;
            final useCommitAnyway =
                state.beacon.coordinationStatus ==
                BeaconCoordinationStatus.enoughHelpCommitted;
            final outcome = await CommitmentMessageDialog.show(
              context,
              title: useCommitAnyway
                  ? l10n.dialogCommitAnywayTitle
                  : l10n.dialogCommitTitle,
              hintText: l10n.hintCommitMessage,
              allowEmptyMessage: true,
              showHelpTypeChips: true,
            );
            if (outcome != null && context.mounted) {
              await cubit.commit(
                message: outcome.message,
                helpType: outcome.helpTypeWire,
              );
            }
          }
        : null,
    onWithdraw:
        !hideCommitWithdraw &&
            state.isCommitted &&
            b.allowsWithdrawWhileCommitted
        ? () async {
            if (!context.mounted) return;
            final outcome = await CommitmentMessageDialog.show(
              context,
              title: l10n.dialogWithdrawTitle,
              hintText: l10n.hintWithdrawReason,
              allowEmptyMessage: true,
              requireUncommitReason: true,
            );
            if (outcome?.uncommitReasonWire != null && context.mounted) {
              await cubit.withdraw(
                message: outcome!.message,
                uncommitReason: outcome.uncommitReasonWire!,
              );
            }
          }
        : null,
    onForward: hideOverflowForward
        ? null
        : () => unawaited(
            context.router.pushPath('$kPathForwardBeacon/$beaconId'),
          ),
    onViewForwards: () => unawaited(
      context.router.pushPath('$kPathBeaconForwards/$beaconId'),
    ),
    onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
    onWatch: state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching: state.inboxStatus == InboxItemStatus.watching
        ? () => unawaited(cubit.stopWatching())
        : null,
    onCantHelp:
        state.inboxStatus == InboxItemStatus.needsMe ||
            state.inboxStatus == InboxItemStatus.watching
        ? () async {
            if (!context.mounted) return;
            final msg = await showRejectionDialog(context);
            if (context.mounted && msg != null) {
              await cubit.rejectInbox(message: msg);
            }
          }
        : null,
    onMoveToInbox: state.inboxStatus == InboxItemStatus.rejected
        ? () => unawaited(cubit.unrejectInbox())
        : null,
    onComplaint: () => screenCubit.showComplaint(beaconId),
  );
}

@RoutePage()
class BeaconViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    @QueryParam(kQueryBeaconViewTab) this.viewTab,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  /// `overview` | `commitments` | `activity` (legacy: `timeline`, `details`, `forwards`).
  final String? viewTab;

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
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;
    final isFromDeepLink = isDeepLink == 'true';
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
      builder: (context, state) {
        final scheme = Theme.of(context).colorScheme;
        final showInitialLoading =
            state.isLoading &&
            state.timeline.isEmpty &&
            state.commitments.isEmpty;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: InboxStyleAppBar.toolbarHeight,
            leadingWidth: InboxStyleAppBar.toolbarHeight,
            foregroundColor: scheme.onSurface,
            titleSpacing: 8,
            leading: isFromDeepLink
                ? BackButton(
                    onPressed: () =>
                        AutoRouter.of(context).navigatePath(kPathHome),
                  )
                : const AutoLeadingButton(),
            title: Text(l10n.beaconViewTitle),
            actions: [
              _beaconViewAppBarOverflow(
                context: context,
                state: state,
                cubit: beaconViewCubit,
                screenCubit: screenCubit,
                l10n: l10n,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearPiActive.builder(context, state.isLoading),
            ),
          ),
          body: showInitialLoading
              ? const Center(
                  child: CircularProgressIndicator.adaptive(),
                )
              : _BeaconOperationalScrollView(
                  beaconViewCubit: beaconViewCubit,
                  screenCubit: screenCubit,
                  initialTabIndex: _beaconViewTabIndex(viewTab),
                ),
        );
      },
    );
  }
}

class _BeaconOperationalScrollView extends StatefulWidget {
  const _BeaconOperationalScrollView({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.initialTabIndex,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int initialTabIndex;

  @override
  State<_BeaconOperationalScrollView> createState() =>
      _BeaconOperationalScrollViewState();
}

class _BeaconOperationalScrollViewState
    extends State<_BeaconOperationalScrollView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickCoordinationStatus(BuildContext context) async {
    await showBeaconCoordinationStatusBottomSheet(
      context: context,
      onPick: (s) => unawaited(
        widget.beaconViewCubit.setBeaconCoordinationStatus(
          BeaconCoordinationStatus.fromSmallint(s),
        ),
      ),
    );
  }

  Future<void> _runCommitFlow(BuildContext context, L10n l10n) async {
    if (!context.mounted) return;
    final useCommitAnyway =
        widget.beaconViewCubit.state.beacon.coordinationStatus ==
        BeaconCoordinationStatus.enoughHelpCommitted;
    final outcome = await CommitmentMessageDialog.show(
      context,
      title: useCommitAnyway
          ? l10n.dialogCommitAnywayTitle
          : l10n.dialogCommitTitle,
      hintText: l10n.hintCommitMessage,
      allowEmptyMessage: true,
      showHelpTypeChips: true,
    );
    if (outcome != null && context.mounted) {
      await widget.beaconViewCubit.commit(
        message: outcome.message,
        helpType: outcome.helpTypeWire,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: widget.beaconViewCubit,
      buildWhen: (p, c) =>
          p.beacon != c.beacon ||
          p.timeline != c.timeline ||
          p.commitments != c.commitments ||
          p.isCommitted != c.isCommitted ||
          p.isLoading != c.isLoading ||
          p.forwardProvenance != c.forwardProvenance ||
          p.inboxStatus != c.inboxStatus ||
          p.viewerForwardEdges != c.viewerForwardEdges,
      builder: (context, state) {
        final beaconId = state.beacon.id;
        return NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _BeaconDetailHeader(
                  beacon: state.beacon,
                  screenCubit: widget.screenCubit,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedStatusStripDelegate(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSpacingMedium,
                      kSpacingSmall / 2,
                      kSpacingMedium,
                      kSpacingSmall / 2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BeaconOperationalStatusStrip(state: state),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpacingMedium,
                    0,
                    kSpacingMedium,
                    kSpacingSmall / 2,
                  ),
                  child: BeaconPrimaryCtaBar(
                    state: state,
                    onUpdateStatus: state.isBeaconMine
                        ? () => unawaited(_pickCoordinationStatus(context))
                        : null,
                    onPostUpdate: () => unawaited(
                      _showPostAuthorUpdateSheet(
                        context,
                        widget.beaconViewCubit,
                        l10n,
                      ),
                    ),
                    onCommit: () => _runCommitFlow(context, l10n),
                    onForward: () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/$beaconId'),
                    ),
                    onViewChain: () =>
                        widget.screenCubit.showForwardsGraphFor(beaconId),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedSegmentBarDelegate(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kSpacingMedium,
                    ),
                    child: Align(
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            padding: WidgetStatePropertyAll(
                              EdgeInsets.symmetric(
                                horizontal: kSpacingSmall / 2,
                                vertical: kSpacingSmall / 2,
                              ),
                            ),
                            minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                          ),
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: _BeaconTabSegmentLabel(
                                l10n.labelBeaconTabOverview,
                              ),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: _BeaconTabSegmentLabel(
                                l10n.labelCommitments,
                              ),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: _BeaconTabSegmentLabel(
                                l10n.labelBeaconTabActivity,
                              ),
                            ),
                          ],
                          selected: {_tabController.index},
                          onSelectionChanged: (s) {
                            final i = s.first;
                            _tabController.animateTo(i);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _BeaconTabScroll(
                tabKey: const PageStorageKey<String>('beacon-overview'),
                contentPadding: const EdgeInsets.fromLTRB(
                  kSpacingMedium,
                  kSpacingSmall / 2,
                  kSpacingMedium,
                  kSpacingSmall,
                ),
                child: BeaconOverviewTab(
                  state: state,
                  onViewAllCommitments: () => _tabController.animateTo(1),
                  onEditTimelineUpdate: (u) => _showEditAuthorUpdateSheet(
                    context,
                    widget.beaconViewCubit,
                    l10n,
                    initial: u.content,
                    updateId: u.id,
                    createdAt: u.createdAt,
                  ),
                ),
              ),
              _BeaconTabScroll(
                tabKey: const PageStorageKey<String>('beacon-commitments'),
                child: _CommitmentsTabBody(
                  state: state,
                  beaconViewCubit: widget.beaconViewCubit,
                  l10n: l10n,
                ),
              ),
              _BeaconTabScroll(
                tabKey: const PageStorageKey<String>('beacon-activity'),
                child: BeaconActivityList(
                  timeline: state.timeline,
                  beacon: state.beacon,
                  isAuthorView: state.isBeaconMine,
                  onEditTimelineUpdate: (u) => _showEditAuthorUpdateSheet(
                    context,
                    widget.beaconViewCubit,
                    l10n,
                    initial: u.content,
                    updateId: u.id,
                    createdAt: u.createdAt,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Beacon identity, title, and author row: same block layout as My Desk cards, without
/// [BeaconCardShell] or a separate surface, and without the metadata “update” line.
class _BeaconDetailHeader extends StatelessWidget {
  const _BeaconDetailHeader({
    required this.beacon,
    required this.screenCubit,
  });

  final Beacon beacon;
  final ScreenCubit screenCubit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kSpacingMedium,
        kSpacingSmall,
        kSpacingMedium,
        kSpacingSmall / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BeaconCardHeaderRow(
            beacon: beacon,
            menu: const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => screenCubit.showProfile(beacon.author.id),
            child: BeaconCardAuthorSubline(
              author: beacon.author,
              category: BeaconCardCategoryMeta(beacon: beacon),
            ),
          ),
        ],
      ),
    );
  }
}

class _BeaconTabSegmentLabel extends StatelessWidget {
  const _BeaconTabSegmentLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Pinned status strip under [NestedScrollView] (fixed height; see tab bar).
class _PinnedStatusStripDelegate extends SliverPersistentHeaderDelegate {
  _PinnedStatusStripDelegate({required this.child});

  final Widget child;

  static const double _height = 48;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 0.5 : 0,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedStatusStripDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// Pinned tab bar: fixed height so layoutExtent matches paintExtent under
/// NestedScrollView (avoids invalid SliverGeometry on web).
class _PinnedSegmentBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSegmentBarDelegate({required this.child});

  final Widget child;

  static const double _barHeight = 56;

  @override
  double get minExtent => _barHeight;

  @override
  double get maxExtent => _barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 0.5 : 0,
      child: SizedBox(
        height: _barHeight,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSegmentBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

class _BeaconTabScroll extends StatelessWidget {
  const _BeaconTabScroll({
    required this.tabKey,
    required this.child,
    this.contentPadding = kPaddingAll,
  });

  final PageStorageKey<String> tabKey;
  final Widget child;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: tabKey,
      slivers: [
        SliverPadding(
          padding: contentPadding,
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class _CommitmentsTabBody extends StatelessWidget {
  const _CommitmentsTabBody({
    required this.state,
    required this.beaconViewCubit,
    required this.l10n,
  });

  final BeaconViewState state;
  final BeaconViewCubit beaconViewCubit;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final beacon = state.beacon;
    final active = state.commitments
        .where((c) => !c.isWithdrawn)
        .toList(growable: false);
    final withdrawn = state.commitments
        .where((c) => c.isWithdrawn)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeaconEvaluationHooks(
          beaconId: beacon.id,
          lifecycle: beacon.lifecycle,
        ),
        for (final c in active)
          CommitmentTile(
            commitment: c,
            beaconAuthor: beacon.author,
            isMine: c.user.id == state.myProfile.id,
            isAuthorView: state.isBeaconMine,
            onAuthorTapCoordination: state.isBeaconMine && !c.isWithdrawn
                ? () => unawaited(
                    showCoordinationResponseBottomSheet(
                      context: context,
                      commitUserTitle: c.user.title,
                      onPick: (t) => unawaited(
                        beaconViewCubit.setCoordinationResponse(
                          commitUserId: c.user.id,
                          responseType: t,
                        ),
                      ),
                    ),
                  )
                : null,
            onEdit: c.user.id == state.myProfile.id && !c.isWithdrawn
                ? () async {
                    final outcome = await CommitmentMessageDialog.show(
                      context,
                      title: l10n.dialogUpdateCommitTitle,
                      hintText: l10n.hintCommitMessage,
                      initialText: c.message,
                    );
                    if (outcome != null &&
                        outcome.message.isNotEmpty &&
                        context.mounted) {
                      await beaconViewCubit.commit(message: outcome.message);
                    }
                  }
                : null,
            onWithdraw:
                c.user.id == state.myProfile.id &&
                    !c.isWithdrawn &&
                    beacon.allowsWithdrawWhileCommitted
                ? () async {
                    final outcome = await CommitmentMessageDialog.show(
                      context,
                      title: l10n.dialogWithdrawTitle,
                      hintText: l10n.hintWithdrawReason,
                      allowEmptyMessage: true,
                      requireUncommitReason: true,
                    );
                    if (outcome?.uncommitReasonWire != null &&
                        context.mounted) {
                      await beaconViewCubit.withdraw(
                        message: outcome!.message,
                        uncommitReason: outcome.uncommitReasonWire!,
                      );
                    }
                  }
                : null,
          ),
        if (withdrawn.isNotEmpty)
          ExpansionTile(
            title: Text(l10n.beaconShowWithdrawn(withdrawn.length)),
            children: [
              for (final c in withdrawn)
                CommitmentTile(
                  commitment: c,
                  beaconAuthor: beacon.author,
                  isMine: c.user.id == state.myProfile.id,
                  isAuthorView: state.isBeaconMine,
                ),
            ],
          ),
      ],
    );
  }
}

Future<void> _showPostAuthorUpdateSheet(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  final controller = TextEditingController();
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: kSpacingSmall,
            right: kSpacingSmall,
            top: kSpacingMedium,
            bottom: bottom + kSpacingMedium,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.postUpdateCTA,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingSmall),
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: kDescriptionMaxLength,
                decoration: InputDecoration(
                  hintText: l10n.beaconUpdateComposerHint,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconUpdateEditWindowHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.of(ctx).pop(true);
                },
                child: Text(l10n.postUpdateCTA),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) {
      final t = controller.text.trim();
      if (t.isNotEmpty) await cubit.postAuthorUpdate(t);
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _showEditAuthorUpdateSheet(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n, {
  required String initial,
  required String updateId,
  required DateTime createdAt,
}) async {
  if (!_authorUpdateEditableNow(createdAt)) {
    if (context.mounted) {
      showSnackBar(
        context,
        isError: true,
        text: l10n.beaconUpdateEditExpired,
      );
    }
    return;
  }
  final controller = TextEditingController(text: initial);
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: kSpacingSmall,
            right: kSpacingSmall,
            top: kSpacingMedium,
            bottom: bottom + kSpacingMedium,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.editUpdateCTA,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingSmall),
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: kDescriptionMaxLength,
                decoration: InputDecoration(
                  hintText: l10n.beaconUpdateComposerHint,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconUpdateEditWindowHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.of(ctx).pop(true);
                },
                child: Text(l10n.buttonSaveChanges),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) {
      final t = controller.text.trim();
      if (t.isNotEmpty && t != initial) {
        await cubit.editAuthorUpdate(id: updateId, content: t);
      }
    }
  } finally {
    controller.dispose();
  }
}
