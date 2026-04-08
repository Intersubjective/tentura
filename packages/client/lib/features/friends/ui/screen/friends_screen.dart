import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/chat/ui/widget/chat_peer_list_tile.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
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
          appBar: AppBar(
            title: Text(l10n.friendsTitle),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.link),
                tooltip: l10n.friendsEnterCode,
                onPressed: () => unawaited(ConnectBottomSheet.show(context)),
              ),
              IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: l10n.friendsCreateInvitation,
                onPressed: () => unawaited(_onCreateInvitation(context)),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BlocSelector<InvitationCubit, InvitationState, bool>(
                    key: Key('Friends.InvitationLoader:${_invitationCubit.hashCode}'),
                    selector: (state) => state.isLoading,
                    builder: LinearPiActive.builder,
                    bloc: _invitationCubit,
                  ),
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: l10n.friendsTitle),
                      Tab(text: l10n.invitationScreenTitle),
                    ],
                  ),
                ],
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
                    return ChatPeerListTile(
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
  });

  final InvitationCubit invitationCubit;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      onRefresh: invitationCubit.fetch,
      child: BlocBuilder<InvitationCubit, InvitationState>(
        key: Key('Friends.InvitesBody:${invitationCubit.hashCode}'),
        bloc: invitationCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          if (state.invitations.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: Center(
                    child: Text(
                      l10n.labelNothingHere,
                      style: Theme.of(context).textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            itemCount: state.invitations.length,
            itemBuilder: (_, i) {
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
                    if (await InvitationRemoveDialog.show(context) ?? false) {
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
            separatorBuilder: separatorBuilder,
          );
        },
      ),
    );
  }
}
