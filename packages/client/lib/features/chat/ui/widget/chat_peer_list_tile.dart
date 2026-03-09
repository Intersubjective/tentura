import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../bloc/chat_news_cubit.dart';

class ChatPeerListTile extends StatelessWidget {
  const ChatPeerListTile({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      // Avatar
      leading: GestureDetector(
        onTap: () => context.read<ScreenCubit>().showProfile(profile.id),
        child: AvatarRated.small(profile: profile),
      ),

      // Title
      title: Text(
        profile.title,
        style: profile.isSeeingMe
            ? const TextStyle(decoration: TextDecoration.underline)
            : null,
      ),

      // New messages indicator
      trailing: BlocSelector<ChatNewsCubit, ChatNewsState, int>(
        bloc: GetIt.I<ChatNewsCubit>(),
        selector: (state) => state.messages[profile.id]?.length ?? 0,
        builder: (_, newMessagesCount) => Badge.count(
          count: newMessagesCount,
          isLabelVisible: newMessagesCount > 0,
          backgroundColor: colorScheme.primaryContainer,
          textColor: colorScheme.onPrimaryContainer,
        ),
      ),

      onTap: profile.isSeeingMe
          ? () => context.read<ScreenCubit>().showChatWith(profile.id)
          : null,
    );
  }
}
