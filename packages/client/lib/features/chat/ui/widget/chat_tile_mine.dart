import 'package:flutter/material.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../bloc/chat_cubit.dart';
import 'chat_message_actions.dart';

class ChatTileMine extends StatelessWidget {
  const ChatTileMine({
    required this.message,
    super.key,
  });

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPress: () => showChatMessageActions(context, message),
      child: Align(
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeFormatHm(message.createdAt.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 4),
                        _ReceiptStatusRow(message: message),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptStatusRow extends StatelessWidget {
  const _ReceiptStatusRow({required this.message});

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    switch (message.status) {
      case ChatMessageStatus.sending:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color,
          ),
        );
      case ChatMessageStatus.sent:
        return Icon(
          Icons.done,
          size: 16,
          color: color,
        );
      case ChatMessageStatus.seen:
        return Icon(
          Icons.done_all,
          size: 16,
          color: primary,
        );
      case ChatMessageStatus.error:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 2),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => context.read<ChatCubit>().onRetrySend(
                    message.clientId,
                  ),
              child: Text(
                L10n.of(context)!.chatMessageRetry,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        );
      case ChatMessageStatus.init:
      case ChatMessageStatus.clear:
        return const SizedBox.shrink();
    }
  }
}
