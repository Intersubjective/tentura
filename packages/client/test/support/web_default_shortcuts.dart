import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// The keyboard entries of `WidgetsApp`'s default shortcuts on the web
/// (`kIsWeb`), which widget tests (run on the VM) never get: there Space
/// maps to [ActivateIntent] first, but Enter and numpad Enter map to
/// [ButtonActivateIntent], so a control that only handles [ActivateIntent]
/// opens with Space and ignores Enter in the browser (#391).
///
/// Pass as `MaterialApp.shortcuts`, or wrap the widget under test in
/// `Shortcuts(shortcuts: webDefaultShortcuts, ...)`.
const webDefaultShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.space): PrioritizedIntents(
    orderedIntents: <Intent>[
      ActivateIntent(),
      ScrollIntent(
        direction: AxisDirection.down,
        type: ScrollIncrementType.page,
      ),
    ],
  ),
  SingleActivator(LogicalKeyboardKey.enter): ButtonActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ButtonActivateIntent(),
  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
  SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): PreviousFocusIntent(),
};
