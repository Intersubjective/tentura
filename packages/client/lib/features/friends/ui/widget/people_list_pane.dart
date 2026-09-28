import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/friends_cubit.dart';
import '../screen/friends_screen.dart';

/// My people as the list pane beside a profile (Material 3 list-detail).
///
/// Its own top bar, as every pane has; no invitation tab or invite prompts —
/// those belong to the full My people screen.
class PeopleListPane extends StatelessWidget {
  const PeopleListPane({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        title: Text(l10n.network),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
        child: FriendsListBody(friendsCubit: GetIt.I<FriendsCubit>()),
      ),
    );
  }
}
