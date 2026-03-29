import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../bloc/chat_news_cubit.dart';
import '../message/chat_messages.dart';
import 'peer_presence_subtitle.dart';

class ChatPeerListTile extends StatelessWidget {
  const ChatPeerListTile({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenCubit = context.read<ScreenCubit>();
    return ListTile(
      leading: AvatarRated.small(profile: profile),

      title: Text(
        profile.title,
        style: profile.isSeeingMe
            ? const TextStyle(decoration: TextDecoration.underline)
            : null,
      ),

      subtitle: BlocBuilder<ChatNewsCubit, ChatNewsState>(
        bloc: GetIt.I<ChatNewsCubit>(),
        buildWhen: (p, c) => p.lastUpdate != c.lastUpdate,
        builder: (context, newsState) {
          final l10n = L10n.of(context)!;
          final presence = newsState.peerPresence[profile.id];
          final last = newsState.lastMessageByPeerId[profile.id];
          final presenceLine = peerPresenceSubtitle(
            l10n: l10n,
            presence: presence,
            isTyping: false,
          );
          final preview = last == null
              ? null
              : (last.content.length > 48
                  ? '${last.content.substring(0, 48)}…'
                  : last.content);
          if (preview == null && presenceLine.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview != null)
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (presenceLine.isNotEmpty)
                Text(
                  presenceLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),

      trailing: BlocBuilder<ChatNewsCubit, ChatNewsState>(
        bloc: GetIt.I<ChatNewsCubit>(),
        buildWhen: (p, c) => p.lastUpdate != c.lastUpdate,
        builder: (context, newsState) {
          final newMessagesCount =
              newsState.messages[profile.id]?.length ?? 0;
          final last = newsState.lastMessageByPeerId[profile.id];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    timeFormatHm(last.createdAt.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              Badge.count(
                count: newMessagesCount,
                isLabelVisible: newMessagesCount > 0,
                backgroundColor: colorScheme.primaryContainer,
                textColor: colorScheme.onPrimaryContainer,
              ),
            ],
          );
        },
      ),

      onTap: () {
        if (profile.isSeeingMe) {
          screenCubit.showChatWith(profile.id);
        } else {
          screenCubit.showMessaging(const NoTrustPathForChatMessage());
        }
      },
    );
  }
}
