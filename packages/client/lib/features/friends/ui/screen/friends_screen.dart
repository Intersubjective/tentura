import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/env.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/chat/ui/widget/chat_peer_list_tile.dart';

import '../bloc/friends_cubit.dart';

@RoutePage()
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final friendsCubit = GetIt.I<FriendsCubit>();
    final env = GetIt.I<Env>();
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: env.needInviteCode
          ? AppBar(
              title: Text(l10n.friendsTitle),
              actions: [
                PopupMenuButton<void>(
                  itemBuilder: (_) => <PopupMenuEntry<void>>[
                    PopupMenuItem(
                      onTap: screenCubit.showInvitations,
                      child: Text(l10n.invitationsShowMenuItem),
                    ),
                  ],
                ),
              ],
              automaticallyImplyLeading: false,
            )
          : null,
      body: BlocBuilder<FriendsCubit, FriendsState>(
        bloc: friendsCubit,
        buildWhen: (_, c) => c.isSuccess,
        builder: (_, state) {
          late final friends = state.friends.values.toList();
          return RefreshIndicator.adaptive(
            onRefresh: friendsCubit.fetch,
            child: state.friends.isEmpty
                // Empty state
                ? Center(
                    child: Text(
                      l10n.labelNothingHere,
                      style: theme.textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                  )
                // Friends List
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
      ),
    );
  }
}
