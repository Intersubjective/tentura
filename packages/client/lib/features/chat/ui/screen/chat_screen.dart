import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/chat_cubit.dart';
import '../dialog/on_chat_clear_dialog.dart';
import '../widget/chat_list.dart';

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
            AutoRouter.of(context).navigatePath(kPathFriends),
      ),
      title: BlocSelector<ChatCubit, ChatState, Profile>(
        selector: (state) => state.friend,
        builder: (_, profile) => Row(
          children: [
            AvatarRated(
              profile: profile,
              size: 32,
            ),
            Expanded(
              child: Padding(
                padding: kPaddingH,
                child: Text(
                  profile.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
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
                      text: 'Not implemented yet...',
                    );
                    await context.read<ChatCubit>().onChatClear();
                  }
                }
              },
              child: const Text('Clear chat'),
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
