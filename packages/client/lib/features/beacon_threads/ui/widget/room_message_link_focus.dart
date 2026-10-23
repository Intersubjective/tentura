import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

/// Keyboard stops for the links in a message's text (#617).
///
/// A link inside the text is a span of a single paragraph, and a span cannot
/// take keyboard focus, so Tab skipped every link and Enter could not open
/// one. This adds one Tab stop per link, in text order, right after the
/// bubble itself: Enter opens the link, and [builder] gets the focused link's
/// URL so the text can draw it highlighted (the stops have no visible box of
/// their own). Each stop is a labelled link semantics node marked focused, so
/// on the web the browser's focus follows Flutter's (see #415).
class RoomMessageLinkFocus extends StatefulWidget {
  const RoomMessageLinkFocus({
    required this.text,
    required this.builder,
    this.onOpenLink,
    super.key,
  });

  /// The message text the links are found in.
  final String text;

  /// Builds the text; `focusedUrl` is the link holding keyboard focus.
  final Widget Function(BuildContext context, String? focusedUrl) builder;

  /// Defaults to opening the link like a tap on it does.
  final Future<void> Function(Uri uri)? onOpenLink;

  @override
  State<RoomMessageLinkFocus> createState() => _RoomMessageLinkFocusState();
}

class _RoomMessageLinkFocusState extends State<RoomMessageLinkFocus> {
  var _urls = const <String>[];

  var _nodes = const <FocusNode>[];

  String? _focusedUrl;

  @override
  void initState() {
    super.initState();
    _setUrls();
  }

  @override
  void didUpdateWidget(RoomMessageLinkFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeNodes();
      _setUrls();
    }
  }

  @override
  void dispose() {
    _disposeNodes();
    super.dispose();
  }

  void _setUrls() {
    _urls = [
      for (final range in findUrlRanges(widget.text))
        range.textInside(widget.text),
    ];
    _nodes = [
      for (var i = 0; i < _urls.length; i++)
        FocusNode(debugLabel: 'RoomMessageLink $i'),
    ];
    _focusedUrl = null;
  }

  void _disposeNodes() {
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes = const [];
  }

  void _open(String url) {
    final uri = Uri.parse(url);
    final open =
        widget.onOpenLink ?? GetIt.I<PlatformRepositoryPort>().launchUserLink;
    unawaited(open(uri));
  }

  void _onFocusChange() {
    String? focused;
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].hasPrimaryFocus) focused = _urls[i];
    }
    if (mounted && focused != _focusedUrl) {
      setState(() => _focusedUrl = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.builder(context, _focusedUrl);
    if (_urls.isEmpty) return text;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        text,
        PositionedDirectional(
          start: 0,
          top: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _urls.length; i++)
                _LinkStop(
                  focusNode: _nodes[i],
                  url: _urls[i],
                  onFocusChange: _onFocusChange,
                  onOpen: () => _open(_urls[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinkStop extends StatelessWidget {
  const _LinkStop({
    required this.focusNode,
    required this.url,
    required this.onFocusChange,
    required this.onOpen,
  });

  final FocusNode focusNode;
  final String url;
  final VoidCallback onFocusChange;
  final VoidCallback onOpen;

  /// Handled here, on the focused link, so the bubble's own Enter (open the
  /// message actions) does not see it.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    onOpen();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      includeSemantics: false,
      onFocusChange: (_) => onFocusChange(),
      onKeyEvent: _onKeyEvent,
      child: Semantics(
        link: true,
        label: url,
        focused: focusNode.hasPrimaryFocus,
        onFocus: focusNode.requestFocus,
        onTap: onOpen,
        // One logical pixel: an empty rect would drop the semantics node.
        child: const SizedBox.square(dimension: 1),
      ),
    );
  }
}
