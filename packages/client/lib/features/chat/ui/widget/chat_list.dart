import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  final _inputFocusNode = FocusNode();

  final _itemScrollController = ItemScrollController();

  final _scrollOffsetController = ScrollOffsetController();

  final _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    _inputFocusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final chatCubit = context.read<ChatCubit>();
    final maxIndex = positions.map((p) => p.index).reduce(
      (a, b) => a > b ? a : b,
    );

    if (maxIndex >= chatCubit.state.messages.length - 1) {
      chatCubit.loadMoreHistory();
    }
  }

  bool _isEnterKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  Future<void> _sendMessage() async {
    final chatCubit = context.read<ChatCubit>();
    FocusScope.of(context).unfocus();
    await chatCubit.onSendPressed(_inputController.text);
    _inputController.clear();
    await _scrollOffsetController.animateScroll(
      duration: const Duration(microseconds: 500),
      offset: 1,
    );
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
            itemPositionsListener: _itemPositionsListener,

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
          child: Focus(
            focusNode: _inputFocusNode,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              if (!_isEnterKey(event.logicalKey)) {
                return KeyEventResult.ignored;
              }
              if (HardwareKeyboard.instance.isShiftPressed) {
                return KeyEventResult.ignored;
              }
              unawaited(_sendMessage());
              return KeyEventResult.handled;
            },
            child: TextField(
              focusNode: _inputFocusNode,
              controller: _inputController,
              onChanged: (value) =>
                  context.read<ChatCubit>().onComposerTextChanged(value),
              decoration: InputDecoration(
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(32)),
                ),
                filled: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => unawaited(_sendMessage()),
                ),
              ),
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              minLines: 1,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ),
      ],
    );
  }
}
