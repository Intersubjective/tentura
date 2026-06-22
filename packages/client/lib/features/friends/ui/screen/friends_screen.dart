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
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/domain/capability/friend_context.dart';

import '../bloc/friends_cubit.dart';

@RoutePage()
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

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
    _tabController = TabController(length: 2, vsync: this);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;

    return BlocProvider.value(
      value: _invitationCubit,
      child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: InboxStyleAppBar(
            title: BlocSelector<InvitationCubit, InvitationState, int>(
              bloc: _invitationCubit,
              selector: (s) => s.invitations.length,
              builder: (context, inviteCount) {
                return TabBar(
                  controller: _tabController,
                  automaticIndicatorColorAdjustment: false,
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  labelPadding: EdgeInsets.symmetric(
                    horizontal: context.tt.tightGap,
                  ),
                  labelColor: scheme.onPrimary,
                  unselectedLabelColor: scheme.onPrimary.withValues(
                    alpha: 0.72,
                  ),
                  indicatorColor: scheme.onPrimary,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimary,
                  ),
                  unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onPrimary.withValues(alpha: 0.72),
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(LinearPiActive.height),
              child: BlocSelector<InvitationCubit, InvitationState, bool>(
                key: Key(
                  'Friends.InvitationLoader:${_invitationCubit.hashCode}',
                ),
                bloc: _invitationCubit,
                selector: (state) => state.isLoading,
                builder: (context, isLoading) {
                  final onPrimary = Theme.of(context).colorScheme.onPrimary;
                  return LinearPiActive.builder(
                    context,
                    isLoading,
                    color: onPrimary.withValues(alpha: 0.85),
                    backgroundColor: onPrimary.withValues(alpha: 0.15),
                  );
                },
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _FriendsTabBody(
                friendsCubit: friendsCubit,
                theme: theme,
                l10n: l10n,
              ),
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
    );
  }
}

class _FriendsTabBody extends StatelessWidget {
  const _FriendsTabBody({
    required this.friendsCubit,
    required this.theme,
    required this.l10n,
  });

  final FriendsCubit friendsCubit;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FriendsCubit, FriendsState>(
      bloc: friendsCubit,
      buildWhen: (_, c) => c.isSuccess,
      builder: (_, state) {
        final friends = state.friends.values.toList();
        return RefreshIndicator.adaptive(
          onRefresh: friendsCubit.fetch,
          child: state.friends.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.5,
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
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RefreshIndicator.adaptive(
      onRefresh: invitationCubit.fetch,
      child: BlocBuilder<InvitationCubit, InvitationState>(
        key: Key('Friends.InvitesBody:${invitationCubit.hashCode}'),
        bloc: invitationCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          return CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (state.invitations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: kPaddingAll,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 64,
                              color: onSurfaceVariant,
                            ),
                            const SizedBox(height: kSpacingMedium),
                            Text(
                              l10n.friendsInvitesEmptyTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: kSpacingSmall),
                            Text(
                              l10n.friendsInvitesEmptyBody,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: kSpacingMedium),
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
              else
                SliverList.separated(
                  itemCount: state.invitations.length,
                  separatorBuilder: separatorBuilder,
                  itemBuilder: (context, i) {
                    final invitation = state.invitations[i];
                    if (state.invitations.length > kFetchListOffset &&
                        state.invitations.length == i + 1) {
                      unawaited(invitationCubit.fetch(clear: false));
                    }
                    final emphasize =
                        invitation.id == emphasizedInvitationId &&
                        !disableAnimations;
                    final addressee = invitation.addresseeName;
                    final name = addressee == null || addressee.isEmpty
                        ? invitation.id
                        : addressee;
                    return _InviteListTile(
                      key: ValueKey(invitation),
                      emphasize: emphasize,
                      title: invitation.beaconTitle != null
                          ? '$name — ${invitation.beaconTitle}'
                          : name,
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
                        if (await InvitationRemoveDialog.show(context) ??
                            false) {
                          await invitationCubit.deleteInvitationById(
                            invitation.id,
                          );
                        }
                      },
                      onTap: () => ShareCodeDialog.show(
                        context,
                        header: l10n.labelInvitationCode,
                        link: inviteShareUri(invitation.id),
                      ),
                    );
                  },
                ),
            ],
          );
        },
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
