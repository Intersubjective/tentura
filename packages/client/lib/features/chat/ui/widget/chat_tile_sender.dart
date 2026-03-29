import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../bloc/chat_cubit.dart';
import 'chat_message_actions.dart';

class ChatTileSender extends StatelessWidget {
  const ChatTileSender({
    required this.message,
    super.key,
  });

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentWidget = Padding(
      padding: kPaddingAllS,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SelectableText(
              message.content,
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              timeFormatHm(message.createdAt.toLocal()),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
    final bubble = ColoredBox(
      color: theme.colorScheme.surfaceBright,
      child: message.status == ChatMessageStatus.sent
          ? VisibilityDetector(
              key: ValueKey(message),
              onVisibilityChanged: (info) async {
                if (info.visibleFraction == 1) {
                  await context.read<ChatCubit>().onMessageShown(message);
                }
              },
              child: contentWidget,
            )
          : contentWidget,
    );
    return GestureDetector(
      onLongPress: () => showChatMessageActions(context, message),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomLeft: Radius.circular(-10),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          child: bubble,
        ),
      ),
    );
  }
}
