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
    // Two *sibling* InkWells in a Row — no nesting, no gesture-arena competition.
    // Left InkWell covers only the avatar; right InkWell covers the rest.
    return Row(
      children: [
        // Avatar — taps open the peer's profile
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
          child: InkWell(
            onTap: () => screenCubit.showProfile(profile.id),
            customBorder: const CircleBorder(),
            child: AvatarRated.small(profile: profile),
          ),
        ),

        // Title + subtitle + trailing — taps open the chat
        Expanded(
          child: InkWell(
            onTap: () {
              if (profile.isSeeingMe) {
                screenCubit.showChatWith(profile.id);
              } else {
                screenCubit.showMessaging(const NoTrustPathForChatMessage());
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.title,
                          style: profile.isSeeingMe
                              ? const TextStyle(
                                  decoration: TextDecoration.underline,
                                )
                              : null,
                        ),
                        BlocBuilder<ChatNewsCubit, ChatNewsState>(
                          bloc: GetIt.I<ChatNewsCubit>(),
                          buildWhen: (p, c) => p.lastUpdate != c.lastUpdate,
                          builder: (context, newsState) {
                            final l10n = L10n.of(context)!;
                            final presence =
                                newsState.peerPresence[profile.id];
                            final last =
                                newsState.lastMessageByPeerId[profile.id];
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                if (presenceLine.isNotEmpty)
                                  Text(
                                    presenceLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  BlocBuilder<ChatNewsCubit, ChatNewsState>(
                    bloc: GetIt.I<ChatNewsCubit>(),
                    buildWhen: (p, c) => p.lastUpdate != c.lastUpdate,
                    builder: (context, newsState) {
                      final newMessagesCount =
                          newsState.messages[profile.id]?.length ?? 0;
                      final last =
                          newsState.lastMessageByPeerId[profile.id];
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (last != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                timeFormatHm(last.createdAt.toLocal()),
                                style:
                                    Theme.of(context).textTheme.labelSmall,
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
