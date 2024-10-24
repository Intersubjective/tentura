import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/friends_cubit.dart';
import '../widgets/friend_list_tile.dart';

@RoutePage()
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final friendsCubit = GetIt.I<FriendsCubit>();
    return SafeArea(
      child: BlocConsumer<FriendsCubit, FriendsState>(
        bloc: friendsCubit,
        listenWhen: (p, c) => c.hasError,
        listener: showSnackBarError,
        buildWhen: (p, c) => c.hasNoError,
        builder: (context, state) {
          late final friends = state.friends.values.toList();
          return RefreshIndicator.adaptive(
            onRefresh: friendsCubit.fetch,
            child: state.friends.isEmpty

                // Empty state
                ? Center(
                    child: Text(
                      'There is nothing here yet',
                      style: Theme.of(context).textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                  )

                // Friends List
                : ListView.separated(
                    padding: kPaddingAll,
                    itemCount: friends.length,
                    itemBuilder: (context, i) {
                      final profile = friends[i];
                      return FriendListTile(
                        key: ValueKey(profile),
                        profile: profile,
                      );
                    },
                    separatorBuilder: (context, i) => const Divider(),
                  ),
          );
        },
      ),
    );
  }
}
