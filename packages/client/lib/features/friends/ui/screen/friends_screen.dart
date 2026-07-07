import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/domain/capability/friend_context.dart';

import '../bloc/friends_cubit.dart';

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

  Future<void> _onCreateInvitation(BuildContext context) async {
    final l10n = L10n.of(context)!;

    final addresseeName = await InvitationAddresseeDialog.show(context);
    if (addresseeName == null || !context.mounted) return;

    if (_tabController.index != 1) {
      _tabController.animateTo(1);
      if (!MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    final invitation = await _invitationCubit.createInvitation(
      addresseeName: addresseeName,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsCubit = GetIt.I<FriendsCubit>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;

    return BlocProvider.value(
      value: _invitationCubit,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: TenturaTopBar.of(
          context,
          tone: TenturaTopBarTone.primary,
          title: BlocSelector<InvitationCubit, InvitationState, int>(
            bloc: _invitationCubit,
            selector: (s) => s.invitations.length,
            builder: (context, inviteCount) {
              return TenturaPrimaryTabBar(
                controller: _tabController,
                labelPadding: EdgeInsets.symmetric(
                  horizontal: context.tt.tightGap,
                ),
                tabs: [
                  Tab(text: l10n.friendsTitle),
                  Tab(
                    text: '${l10n.invitationScreenTitle} ($inviteCount)',
                  ),
                ],
              );
            },
          ),
          actions: [
            IconButton(
              tooltip: l10n.friendsCreateInvitation,
              onPressed: () => unawaited(_onCreateInvitation(context)),
              icon: const Icon(Icons.person_add_alt_1),
            ),
            IconButton(
              tooltip: l10n.friendsScanInviteCode,
              onPressed: () => unawaited(ConnectBottomSheet.show(context)),
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
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
                _FriendsTabBody(friendsCubit: friendsCubit),
                _InvitesTabBody(
                  invitationCubit: _invitationCubit,
                  scrollController: _invitesScrollController,
                  emphasizedInvitationId: _emphasizedInvitationId,
                  l10n: l10n,
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

class _FriendsTabBody extends StatelessWidget {
  const _FriendsTabBody({required this.friendsCubit});

  final FriendsCubit friendsCubit;

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
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.35,
                      child: Center(
                        child: Text(
                          l10n.labelNothingHere,
                          style: theme.textTheme.displaySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: friends.length,
                  itemBuilder: (_, i) {
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
    required this.onCreateInvitation,
  });

  final InvitationCubit invitationCubit;
  final ScrollController scrollController;
  final String? emphasizedInvitationId;
  final L10n l10n;
  final VoidCallback onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RefreshIndicator.adaptive(
      onRefresh: invitationCubit.fetch,
      child: BlocBuilder<InvitationCubit, InvitationState>(
        key: Key('Friends.InvitesBody:${invitationCubit.hashCode}'),
        bloc: invitationCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          final peopleInvites = state.invitations
              .where((i) => i.beaconId == null || i.beaconId!.isEmpty)
              .toList();
          final beaconInvites = state.invitations
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
              if (state.invitations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: tt.cardPadding,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: tt.contentMaxWidth ?? 320,
                        ),
                        child: Column(
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
                              l10n.friendsInvitesEmptyBody,
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
                      state: state,
                      invitation: peopleInvites[i],
                      disableAnimations: disableAnimations,
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
                        padding: EdgeInsets.fromLTRB(
                          tt.screenHPadding,
                          tt.tightGap,
                          tt.screenHPadding,
                          0,
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
                        state: state,
                        invitation: beaconGroups[groupTitle]![i],
                        disableAnimations: disableAnimations,
                      ),
                    ),
                  ],
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildInviteTile(
    BuildContext context, {
    required InvitationState state,
    required InvitationEntity invitation,
    required bool disableAnimations,
  }) {
    if (state.invitations.length > kFetchListOffset &&
        state.invitations.last == invitation) {
      unawaited(invitationCubit.fetch(clear: false));
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
      subtitle: compactRelativeTimeAgo(
        when: invitation.createdAt,
        now: DateTime.now(),
        l10n: l10n,
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
      ),
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
    const touchTarget = BoxConstraints(minWidth: 44, minHeight: 44);

    final tile = ListTile(
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
