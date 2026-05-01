import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';

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

  late final StreamSubscription<String> _authChanges;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _invitationCubit = InvitationCubit();
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
    unawaited(_invitationCubit.close());
    super.dispose();
  }

  Future<void> _onCreateInvitation(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final invitation = await _invitationCubit.createInvitation();
    if (invitation == null || !context.mounted) return;
    await ShareCodeDialog.show(
      context,
      header: l10n.labelInvitationCode,
      link: Uri.parse(kServerName).replace(
        path: kPathAppLinkView,
        queryParameters: {'id': invitation.id},
      ),
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
      child: MultiBlocListener(
        listeners: const [
          BlocListener<InvitationCubit, InvitationState>(
            listener: commonScreenBlocListener,
          ),
        ],
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
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
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
                      text:
                          '${l10n.invitationScreenTitle} ($inviteCount)',
                    ),
                  ],
                );
              },
            ),
            actions: [
              IconButton(
                tooltip: l10n.friendsEnterCode,
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
                l10n: l10n,
                onCreateInvitation: () =>
                    unawaited(_onCreateInvitation(context)),
              ),
            ],
          ),
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
    required this.l10n,
    required this.onCreateInvitation,
  });

  final InvitationCubit invitationCubit;
  final L10n l10n;
  final VoidCallback onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator.adaptive(
      onRefresh: invitationCubit.fetch,
      child: BlocBuilder<InvitationCubit, InvitationState>(
        key: Key('Friends.InvitesBody:${invitationCubit.hashCode}'),
        bloc: invitationCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(l10n.friendsCreateInvitation),
                      onPressed: onCreateInvitation,
                    ),
                  ),
                ),
              ),
              if (state.invitations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      l10n.labelNothingHere,
                      style: theme.textTheme.displaySmall,
                      textAlign: TextAlign.center,
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
                    final createdAt = invitation.createdAt.toLocal();
                    return ListTile(
                      key: ValueKey(invitation),
                      title: Text(invitation.id),
                      subtitle: Text(
                        '${dateFormatYMD(createdAt)}  ${timeFormatHm(createdAt)}',
                      ),
                      trailing: IconButton(
                        onPressed: () async {
                          if (await InvitationRemoveDialog.show(context) ??
                              false) {
                            await invitationCubit.deleteInvitationById(
                              invitation.id,
                            );
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red[300],
                        ),
                      ),
                      onTap: () => ShareCodeDialog.show(
                        context,
                        header: l10n.labelInvitationCode,
                        link: Uri.parse(kServerName).replace(
                          path: kPathAppLinkView,
                          queryParameters: {'id': invitation.id},
                        ),
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
