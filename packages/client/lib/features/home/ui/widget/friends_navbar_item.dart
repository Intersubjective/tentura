import 'package:flutter/material.dart';

import 'package:tentura/features/chat/ui/bloc/chat_news_cubit.dart';

class FriendsNavbarItem extends StatelessWidget {
  const FriendsNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<ChatNewsCubit, ChatNewsState, int>(
        bloc: GetIt.I<ChatNewsCubit>(),
        selector: (state) => state.countNewTotal,
        builder: (context, countTotal) => Badge.count(
          count: countTotal,
          isLabelVisible: countTotal > 0,
          child: Icon(selected ? Icons.people : Icons.people_outline),
        ),
      );
}
