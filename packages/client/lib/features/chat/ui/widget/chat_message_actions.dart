import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../bloc/chat_cubit.dart';

Future<void> showChatMessageActions(
  BuildContext context,
  ChatMessageEntity message,
) {
  final cubit = context.read<ChatCubit>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(L10n.of(sheetContext)!.chatMessageCopy),
            onTap: () {
              unawaited(
                Clipboard.setData(ClipboardData(text: message.content)),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(L10n.of(sheetContext)!.chatMessageDeleteForMe),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(cubit.deleteMessageForMe(message));
            },
          ),
        ],
      ),
    ),
  );
}
