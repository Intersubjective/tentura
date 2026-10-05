import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../bloc/friends_cubit.dart';
import '../invite_pending_subtitle.dart';
import '../widget/accepted_invite_list_tile.dart';
import '../widget/friends_app_bar_actions.dart';

/// Semantic hook for blocked-people navigation from People.
void navigateToBlockedPeopleFromFriends(BuildContext context) {
  context.read<ScreenCubit>().showBlockedUsers();
}

@RoutePage()
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    @QueryParam(kQueryHomeTab) this.initialTab,
    super.key,
  });

  final String? initialTab;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final InvitationCubit _invitationCubit;
  late final ScrollController _invitesScrollController;

  late final StreamSubscription<String> _authChanges;

  String? _emphasizedInvitationId;

  /// 0 = Pending, 1 = Accepted. Lives here (not inside `_InvitesTabBody`) so
  /// [_onCreateInvitation] can force the view back to Pending.
  int _invitesSegment = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialTab == kHomeTabInvitations ? 1 : 0,
      vsync: this,
    );
    _invitationCubit = InvitationCubit();
    _invitesScrollController = ScrollController();
    _authChanges = GetIt.I<AuthCase>().currentAccountChanges().listen((id) {
      if (id.isEmpty) {
        return;
      }
      unawaited(_invitationCubit.fetch());
    });
  }

  @override
  void dispose() {
    unawaited(_authChanges.cancel());
    _tabController.dispose();
    _invitesScrollController.dispose();
    unawaited(_invitationCubit.close());
    super.dispose();
  }

  void _onOpenGraph(BuildContext context) {
    final accountId = context.read<ProfileCubit>().state.profile.id;
    if (accountId.isEmpty) {
      return;
    }
    context.read<ScreenCubit>().showGraphFor(accountId);
  }

  Future<void> _onCreateInvitation(BuildContext context) async {
    final l10n = L10n.of(context)!;

    if (_tabController.index != 1) {
      _tabController.animateTo(1);
      if (!MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (_invitesSegment != 0) {
      setState(() => _invitesSegment = 0);
    }

    final invitation = await _invitationCubit.createInvitation(
      addresseeName: '',
    );
    if (invitation == null || !context.mounted) return;

    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    setState(() => _emphasizedInvitationId = invitation.id);

    if (disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_invitesScrollController.hasClients || !mounted) return;
        _invitesScrollController.jumpTo(
          _invitesScrollController.position.maxScrollExtent,
        );
      });
      setState(() => _emphasizedInvitationId = null);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_invitesScrollController.hasClients || !mounted) return;
        unawaited(
          _invitesScrollController.animateTo(
            _invitesScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      });
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
          if (mounted) setState(() => _emphasizedInvitationId = null);
        }),
      );
    }

    await ShareCodeDialog.show(
      context,
      header: l10n.labelInvitationCode,
      link: inviteShareUri(invitation.id),
      caption: l10n.invitationDualPurposeBody,
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsCubit = GetIt.I<FriendsCubit>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final compact = context.windowClass == WindowClass.compact;
    final tabBar = BlocSelector<InvitationCubit, InvitationState, int>(
      bloc: _invitationCubit,
      selector: (s) => s.pendingCount,
      builder: (context, inviteCount) {
        return TenturaPrimaryTabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.friendsTitle),
            // No "(0)": a zero count reads as something to look at.
            Tab(
              text: inviteCount > 0
                  ? '${l10n.invitationScreenTitle} ($inviteCount)'
                  : l10n.invitationScreenTitle,
            ),
          ],
        );
      },
    );

    return BlocProvider.value(
      value: _invitationCubit,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: TenturaTopBar.of(
          context,
          tone: TenturaTopBarTone.primary,
          // Wide bars hold the tabs in the title slot. Compact ones cannot
          // fit tabs, actions and the account side by side: they get the
          // standard Material layout — the screen's name in the bar, tabs
          // in a row of their own under it.
          title: compact
              ? Text(
                  l10n.network,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.titleLarge(scheme.onSurface),
                )
              : tabBar,
          bottom: compact
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kTextTabBarHeight),
                  child: tabBar,
                )
              : null,
          actions: [
            FriendsAppBarActions(
              compact: compact,
              onGraph: () => _onOpenGraph(context),
              onCreateInvitation: () => unawaited(_onCreateInvitation(context)),
              onScanInvitationQr: () =>
                  unawaited(ConnectBottomSheet.show(context)),
              onBlockedPeople: () =>
                  navigateToBlockedPeopleFromFriends(context),
            ),
          ],
          account: homeTopBarAccount(context),
          progress: BlocSelector<InvitationCubit, InvitationState, bool>(
            key: Key('Friends.InvitationLoader:${_invitationCubit.hashCode}'),
            bloc: _invitationCubit,
            selector: (state) => state.isLoading,
            builder: (context, isLoading) => TenturaTopBar.loadingBar(
              context,
              isLoading,
              tone: TenturaTopBarTone.primary,
            ),
          ),
        ),
        body: SafeArea(
          minimum: EdgeInsets.symmetric(
            horizontal: context.tt.screenHPadding,
          ),
          child: TenturaContentColumn(
            child: TabBarView(
              controller: _tabController,
              children: [
                FriendsListBody(
                  friendsCubit: friendsCubit,
                  onCreateInvitation: () =>
                      unawaited(_onCreateInvitation(context)),
                ),
                _InvitesTabBody(
                  invitationCubit: _invitationCubit,
                  scrollController: _invitesScrollController,
                  emphasizedInvitationId: _emphasizedInvitationId,
                  l10n: l10n,
                  segment: _invitesSegment,
                  onSegmentChanged: (i) => setState(() => _invitesSegment = i),
                  onCreateInvitation: () =>
                      unawaited(_onCreateInvitation(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trusted-people list: My people's first tab, and the list pane beside
/// a profile on a wide window. Without [onCreateInvitation] (the pane) the
/// invite prompts are left out.
class FriendsListBody extends StatelessWidget {
  const FriendsListBody({
    required this.friendsCubit,
    this.onCreateInvitation,
    super.key,
  });

  /// Below this many people the list leaves most of the screen blank, so an
  /// invite prompt follows it instead of waiting in the app bar.
  static const _inviteFooterBelow = 4;

  final FriendsCubit friendsCubit;
  final VoidCallback? onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<FriendsCubit, FriendsState>(
      bloc: friendsCubit,
      buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
      builder: (_, state) {
        if (state.isLoading && state.friends.isEmpty) {
          return const Center(
            child: CircularProgressIndicator.adaptive(),
          );
        }
        if (state.hasError && state.friends.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: tt.iconSize * 2,
                  color: theme.colorScheme.error,
                ),
                SizedBox(height: tt.sectionGap),
                FilledButton(
                  onPressed: () => unawaited(friendsCubit.fetch()),
                  child: Text(l10n.myWorkRetry),
                ),
              ],
            ),
          );
        }
        final friends = state.friends.values.toList();
        return RefreshIndicator.adaptive(
          onRefresh: friendsCubit.fetch,
          child: state.friends.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: TenturaEmptyState(
                        icon: Icons.people_outline,
                        title: l10n.friendsEmptyTitle,
                        body: l10n.friendsEmptyBody,
                        actionLabel: l10n.friendsCreateInvitation,
                        onAction: onCreateInvitation,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount:
                      friends.length +
                      (onCreateInvitation != null &&
                              friends.length < _inviteFooterBelow
                          ? 1
                          : 0),
                  itemBuilder: (_, i) {
                    if (i == friends.length) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: tt.sectionGap,
                        ),
                        child: Center(
                          child: FilledButton.tonalIcon(
                            key: const Key('Friends.InviteFooter'),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(l10n.friendsInviteMore),
                            onPressed: onCreateInvitation,
                          ),
                        ),
                      );
                    }
                    final profile = friends[i];
                    return NetworkPersonCard(
                      key: ValueKey(profile),
                      profile: profile,
                      friendContext:
                          state.friendContexts[profile.id] ??
                          FriendContext.empty,
                    );
                  },
                  separatorBuilder: separatorBuilder,
                ),
        );
      },
    );
  }
}

class _InvitesTabBody extends StatelessWidget {
  const _InvitesTabBody({
    required this.invitationCubit,
    required this.scrollController,
    required this.emphasizedInvitationId,
    required this.l10n,
    required this.segment,
    required this.onSegmentChanged,
    required this.onCreateInvitation,
  });

  final InvitationCubit invitationCubit;
  final ScrollController scrollController;
  final String? emphasizedInvitationId;
  final L10n l10n;

  /// 0 = Pending, 1 = Accepted.
  final int segment;
  final ValueChanged<int> onSegmentChanged;
  final VoidCallback onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final isAccepted = segment == 1;

    return Column(
      children: [
        TenturaUnderlineTabs(
          tabs: [
            l10n.friendsInvitesSegmentPending,
            l10n.friendsInvitesSegmentAccepted,
          ],
          selectedIndex: segment,
          onChanged: onSegmentChanged,
          tabIds: const [
            'invites-segment-pending',
            'invites-segment-accepted',
          ],
        ),
        SizedBox(height: tt.tightGap),
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: invitationCubit.fetch,
            child: BlocBuilder<InvitationCubit, InvitationState>(
              key: Key('Friends.InvitesBody:${invitationCubit.hashCode}'),
              bloc: invitationCubit,
              buildWhen: (_, c) => c.isSuccess,
              builder: (_, state) => _InvitesSegmentList(
                invitationCubit: invitationCubit,
                scrollController: scrollController,
                emphasizedInvitationId: emphasizedInvitationId,
                l10n: l10n,
                isAccepted: isAccepted,
                segmentInvites: isAccepted
                    ? state.acceptedInvitations
                    : state.pendingInvitations,
                onCreateInvitation: onCreateInvitation,
                onSwitchToPending: () => onSegmentChanged(0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InvitesSegmentList extends StatelessWidget {
  const _InvitesSegmentList({
    required this.invitationCubit,
    required this.scrollController,
    required this.emphasizedInvitationId,
    required this.l10n,
    required this.isAccepted,
    required this.segmentInvites,
    required this.onCreateInvitation,
    required this.onSwitchToPending,
  });

  final InvitationCubit invitationCubit;
  final ScrollController scrollController;
  final String? emphasizedInvitationId;
  final L10n l10n;
  final bool isAccepted;
  final List<InvitationEntity> segmentInvites;
  final VoidCallback onCreateInvitation;
  final VoidCallback onSwitchToPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final peopleInvites = segmentInvites
        .where((i) => i.beaconId == null || i.beaconId!.isEmpty)
        .toList();
    final beaconInvites = segmentInvites
        .where((i) => i.beaconId != null && i.beaconId!.isNotEmpty)
        .toList();
    final beaconGroups = <String, List<InvitationEntity>>{};
    for (final invitation in beaconInvites) {
      final key = invitation.beaconTitle?.trim().isNotEmpty == true
          ? invitation.beaconTitle!.trim()
          : (invitation.beaconId ?? invitation.id);
      beaconGroups.putIfAbsent(key, () => []).add(invitation);
    }
    final beaconGroupKeys = beaconGroups.keys.toList()..sort();

    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (segmentInvites.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: tt.cardPadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: tt.contentMaxWidth ?? 320,
                  ),
                  child: isAccepted
                      ? _AcceptedEmptyState(
                          l10n: l10n,
                          onSwitchToPending: onSwitchToPending,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_outlined,
                              size: tt.iconSize * 3,
                              color: onSurfaceVariant,
                            ),
                            SizedBox(height: tt.sectionGap),
                            Text(
                              l10n.friendsInvitesEmptyTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: tt.rowGap),
                            Text(
                              l10n.invitationDualPurposeBody,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: tt.sectionGap),
                            FilledButton.icon(
                              icon: const Icon(Icons.person_add_alt_1),
                              label: Text(l10n.friendsCreateInvitation),
                              onPressed: onCreateInvitation,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          )
        else ...[
          if (peopleInvites.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  tt.screenHPadding,
                  tt.sectionGap,
                  tt.screenHPadding,
                  tt.rowGap,
                ),
                child: Text(
                  l10n.friendsInvitesPeopleSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: peopleInvites.length,
              separatorBuilder: separatorBuilder,
              itemBuilder: (context, i) => _buildInviteTile(
                context,
                invitation: peopleInvites[i],
                disableAnimations: disableAnimations,
                isBeaconSection: false,
              ),
            ),
          ],
          if (beaconGroupKeys.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  tt.screenHPadding,
                  tt.sectionGap,
                  tt.screenHPadding,
                  tt.rowGap,
                ),
                child: Text(
                  l10n.friendsInvitesBeaconSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
              ),
            ),
            for (final groupTitle in beaconGroupKeys) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: tt.screenHPadding,
                    top: tt.tightGap,
                    right: tt.screenHPadding,
                  ),
                  child: Text(
                    groupTitle,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: beaconGroups[groupTitle]!.length,
                separatorBuilder: separatorBuilder,
                itemBuilder: (context, i) => _buildInviteTile(
                  context,
                  invitation: beaconGroups[groupTitle]![i],
                  disableAnimations: disableAnimations,
                  isBeaconSection: true,
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _buildInviteTile(
    BuildContext context, {
    required InvitationEntity invitation,
    required bool disableAnimations,
    required bool isBeaconSection,
  }) {
    if (segmentInvites.length > kFetchListOffset &&
        segmentInvites.last == invitation) {
      unawaited(
        isAccepted
            ? invitationCubit.fetchMoreAccepted()
            : invitationCubit.fetchMorePending(),
      );
    }

    if (isAccepted) {
      VoidCallback? onTap;
      if (isBeaconSection) {
        final beaconId = invitation.beaconId;
        if (beaconId != null) {
          onTap = () => context.read<ScreenCubit>().showBeacon(beaconId);
        }
      } else if (invitation.invitedName != null ||
          invitation.invitedImageId != null) {
        final invitedId = invitation.invitedId;
        if (invitedId != null) {
          onTap = () => context.read<ScreenCubit>().showProfile(invitedId);
        }
      }
      return AcceptedInviteListTile(
        key: ValueKey(invitation),
        invitation: invitation,
        l10n: l10n,
        onTap: onTap,
      );
    }

    final emphasize =
        invitation.id == emphasizedInvitationId && !disableAnimations;
    final addressee = invitation.addresseeName;
    final name = addressee == null || addressee.isEmpty
        ? invitation.id
        : addressee;
    return _InviteListTile(
      key: ValueKey(invitation),
      emphasize: emphasize,
      title: name,
      subtitle: invitePendingSubtitle(
        l10n: l10n,
        when: invitation.createdAt,
        now: DateTime.now(),
      ),
      onEdit: () async {
        final newName = await InvitationAddresseeDialog.show(
          context,
          initialName: addressee ?? '',
          isEdit: true,
        );
        if (newName == null) return;
        await invitationCubit.updateInvitation(
          id: invitation.id,
          addresseeName: newName,
        );
      },
      onDelete: () async {
        if (await InvitationRemoveDialog.show(context) ?? false) {
          await invitationCubit.deleteInvitationById(invitation.id);
        }
      },
      onTap: () => ShareCodeDialog.show(
        context,
        header: l10n.labelInvitationCode,
        link: inviteShareUri(invitation.id),
        caption: invitation.beaconId == null || invitation.beaconId!.isEmpty
            ? l10n.invitationDualPurposeBody
            : null,
      ),
    );
  }
}

class _AcceptedEmptyState extends StatelessWidget {
  const _AcceptedEmptyState({
    required this.l10n,
    required this.onSwitchToPending,
  });

  final L10n l10n;
  final VoidCallback onSwitchToPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: tt.iconSize * 3,
          color: onSurfaceVariant,
        ),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.friendsInvitesAcceptedEmptyTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tt.rowGap),
        Text(
          l10n.friendsInvitesAcceptedEmptyBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tt.sectionGap),
        TenturaTextAction(
          label: l10n.friendsInvitesAcceptedEmptyBackToPending,
          onPressed: onSwitchToPending,
        ),
      ],
    );
  }
}

class _InviteListTile extends StatelessWidget {
  const _InviteListTile({
    required this.emphasize,
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
    super.key,
  });

  final bool emphasize;
  final String title;
  final String subtitle;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    const touchTarget = BoxConstraints(minWidth: 44, minHeight: 44);

    final tile = ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.sectionGap,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: touchTarget,
            tooltip: l10n.invitationAddresseeEditTitle,
            onPressed: () => unawaited(onEdit()),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: touchTarget,
            tooltip: l10n.buttonDelete,
            onPressed: () => unawaited(onDelete()),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: scheme.error,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );

    if (!emphasize) return tile;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: tile,
    );
  }
}
