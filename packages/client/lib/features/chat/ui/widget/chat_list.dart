import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/chat_cubit.dart';
import 'chat_separator.dart';
import 'chat_tile_sender.dart';
import 'chat_tile_mine.dart';

class ChatList extends StatefulWidget {
  const ChatList({super.key});

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final _inputController = TextEditingController();

  final _itemScrollController = ItemScrollController();

  final _scrollOffsetController = ScrollOffsetController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatCubit = context.watch<ChatCubit>();
    return Column(
      children: [
        // Chat List
        Expanded(
          child: ScrollablePositionedList.separated(
            padding: kPaddingAll,
            reverse: true,
            itemCount: chatCubit.state.messages.length,
            itemScrollController: _itemScrollController,
            scrollOffsetController: _scrollOffsetController,

            // Message Tile
            itemBuilder: (_, index) {
              final message = chatCubit.state.messages[index];
              final key = ValueKey(message);
              return message.senderId == chatCubit.state.me.id
                  ? ChatTileMine(key: key, message: message)
                  : ChatTileSender(key: key, message: message);
            },

            // Time separator
            separatorBuilder: (_, i) => ChatSeparator(
              currentMessage: chatCubit.state.messages[i],
              nextMessage: chatCubit.state.messages[i + 1],
            ),
          ),
        ),

        // Input
        Padding(
          padding: kPaddingAllS,
          child: TextField(
            controller: _inputController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(32)),
              ),
              filled: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await chatCubit.onSendPressed(_inputController.text);
                  _inputController.clear();
                  await _scrollOffsetController.animateScroll(
                    duration: const Duration(microseconds: 500),
                    offset: 1,
                  );
                },
              ),
            ),
            keyboardType: TextInputType.multiline,
            maxLines: 5,
            minLines: 1,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ],
    );
  }
}
