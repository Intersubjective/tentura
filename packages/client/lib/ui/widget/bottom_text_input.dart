import 'package:flutter/material.dart';

class BottomTextInput extends StatefulWidget {
  const BottomTextInput({
    required this.hintText,
    this.onSend,
    super.key,
  });

  final String hintText;

  final Future<void> Function(String text)? onSend;

  @override
  State<BottomTextInput> createState() => _NewCommentInputState();
}

class _NewCommentInputState extends State<BottomTextInput> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20, left: 20),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            decoration: InputDecoration(hintText: widget.hintText),
            maxLines: null,
            readOnly: widget.onSend == null,
            canRequestFocus: widget.onSend != null,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send),
          onPressed: () async {
            if (_textController.text.isEmpty) {
              return;
            }
            try {
              await widget.onSend?.call(_textController.text);
              _textController.clear();
            } catch (_) {}
            if (context.mounted) {
              FocusScope.of(context).unfocus();
            }
          },
        ),
      ],
    ),
  );
}
