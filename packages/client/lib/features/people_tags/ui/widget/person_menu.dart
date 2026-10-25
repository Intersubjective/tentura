import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'add_to_tag_sheet.dart';

/// The person menu's entries: [leading] ones (e.g. "Profile"), then
/// "Add to tag…" for [personId].
List<PopupMenuEntry<void>> personMenuEntries(
  BuildContext context, {
  required String personId,
  List<PopupMenuEntry<void>> leading = const [],
}) => [
  ...leading,
  PopupMenuItem<void>(
    onTap: () => unawaited(showAddToTagSheet(context, personId: personId)),
    child: Text(L10n.of(context)!.peopleTagsAddToTag),
  ),
];

/// The visible overflow button of a person's row; opens the person menu.
class PersonMenuButton extends StatelessWidget {
  const PersonMenuButton({
    required this.personId,
    this.leading = const [],
    super.key,
  });

  final String personId;

  final List<PopupMenuEntry<void>> leading;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    itemBuilder: (_) =>
        personMenuEntries(context, personId: personId, leading: leading),
  );
}

/// Opens the person menu of [personId] on a touch long press or a mouse
/// secondary tap anywhere on [child]. A plain tap is left to [child].
/// With [enabled] false it adds nothing.
class PersonMenuGestures extends StatelessWidget {
  const PersonMenuGestures({
    required this.enabled,
    required this.personId,
    required this.child,
    this.leading = const [],
    super.key,
  });

  final bool enabled;

  final String personId;

  final List<PopupMenuEntry<void>> leading;

  final Widget child;

  static const _touchOrStylus = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  };

  void _showMenuAt(BuildContext context, Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(
          globalPosition & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: personMenuEntries(context, personId: personId, leading: leading),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                supportedDevices: _touchOrStylus,
              ),
              (r) =>
                  r
                    ..onLongPressStart = (details) =>
                        _showMenuAt(context, details.globalPosition),
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) =>
                  r
                    ..onSecondaryTapUp = (details) =>
                        _showMenuAt(context, details.globalPosition),
            ),
      },
      child: child,
    );
  }
}
