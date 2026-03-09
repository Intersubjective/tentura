import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/chat_message_entity.dart';

class ChatTileMine extends StatelessWidget {
  const ChatTileMine({
    required this.message,
    super.key,
  });

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(-10),
        ),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
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
          ),
        ),
      ),
    );
  }
}
