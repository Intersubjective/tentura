import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/chat_cubit.dart';
import '../dialog/on_chat_clear_dialog.dart';
import '../widget/chat_list.dart';
import '../widget/peer_presence_subtitle.dart';

@RoutePage()
class ChatScreen extends StatelessWidget implements AutoRouteWrapper {
  const ChatScreen({
    @PathParam('id') this.id = '',
    @QueryParam('receiver_id') this.receiverId = '',
    super.key,
  });

  final String id;

  final String? receiverId;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ChatCubit(friendId: id),
    child: BlocListener<ChatCubit, ChatState>(
      listener: commonScreenBlocListener,
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(
        onPressed: () async =>
            AutoRouter.of(context).navigatePath(kPathNetwork),
      ),
      title: BlocBuilder<ChatCubit, ChatState>(
        buildWhen: (p, c) =>
            p.friend != c.friend ||
            p.friendPresence != c.friendPresence ||
            p.peerIsTyping != c.peerIsTyping,
        builder: (context, state) {
          final theme = Theme.of(context);
          final l10n = L10n.of(context)!;
          final profile = state.friend;
          final subtitle = peerPresenceSubtitle(
            l10n: l10n,
            presence: state.friendPresence,
            isTyping: state.peerIsTyping,
          );
          return Row(
            children: [
              AvatarRated(
                profile: profile,
                size: 32,
              ),
              Expanded(
                child: Padding(
                  padding: kPaddingH,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            PopupMenuItem(
              onTap: () async {
                if (await OnChatClearDialog.show(context) ?? false) {
                  if (context.mounted) {
                    // TBD: remove when implemented
                    showSnackBar(
                      context,
                      text: L10n.of(context)!.notImplementedYet,
                    );
                    await context.read<ChatCubit>().onChatClear();
                  }
                }
              },
              child: Text(L10n.of(context)!.chatMenuClearChat),
            ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: BlocSelector<ChatCubit, ChatState, bool>(
          selector: (state) => state.isLoading,
          builder: (_, isLoading) =>
              isLoading ? const LinearPiActive() : const SizedBox(height: 4),
        ),
      ),
    ),
    body: const ChatList(),
  );
}
