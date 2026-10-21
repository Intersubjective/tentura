import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// On web, keeps the browser's own context menu off while [child] (a room)
/// is mounted, so right-click over a message reaches our actions (#456).
///
/// The menu is turned off once per mount, not on every bubble hover:
/// Flutter's [SelectableRegion] wraps its content in a browser-menu view
/// only while [BrowserContextMenu.enabled] is on, so a flip under a mounted
/// region crashes its next rebuild into a grey error box (#623). The child
/// is therefore built only once the menu is off, and holds are counted so
/// nested or stacked rooms hand over without turning it back on in between.
/// Off the web this is a plain pass-through.
class BrowserContextMenuHold extends StatefulWidget {
  const BrowserContextMenuHold({
    required this.child,
    super.key,
  });

  final Widget child;

  /// Replaceable in tests, where `kIsWeb` is always false and
  /// [BrowserContextMenu] asserts it runs on web.
  @visibleForTesting
  static bool Function() isWeb = _isWeb;

  @visibleForTesting
  static Future<void> Function() disableMenu =
      BrowserContextMenu.disableContextMenu;

  @visibleForTesting
  static Future<void> Function() enableMenu =
      BrowserContextMenu.enableContextMenu;

  /// How long the room waits for the browser to confirm the menu is off.
  /// Past this it is built anyway, so a call that never returns cannot
  /// leave the room blank.
  static const menuOffWait = Duration(milliseconds: 500);

  /// How many holds are mounted now.
  @visibleForTesting
  static int get activeHolds => _holds;

  static bool _isWeb() => kIsWeb;

  static int _holds = 0;

  /// The browser menu's turn-off request still in flight, if any.
  static Future<void>? _turningOff;

  @override
  State<BrowserContextMenuHold> createState() => _BrowserContextMenuHoldState();
}

class _BrowserContextMenuHoldState extends State<BrowserContextMenuHold> {
  bool _holding = false;
  bool _ready = true;

  @override
  void initState() {
    super.initState();
    if (!BrowserContextMenuHold.isWeb()) return;
    _holding = true;
    if (BrowserContextMenuHold._holds++ == 0) {
      late final Future<void> turningOff;
      turningOff = BrowserContextMenuHold.disableMenu()
          .catchError((Object _) {})
          .whenComplete(() {
            if (identical(BrowserContextMenuHold._turningOff, turningOff)) {
              BrowserContextMenuHold._turningOff = null;
            }
          });
      BrowserContextMenuHold._turningOff = turningOff;
    }
    final pending = BrowserContextMenuHold._turningOff;
    if (pending != null) {
      _ready = false;
      unawaited(
        pending
            .timeout(BrowserContextMenuHold.menuOffWait, onTimeout: () {})
            .whenComplete(() {
              if (mounted && !_ready) setState(() => _ready = true);
            }),
      );
    }
  }

  @override
  void dispose() {
    if (_holding && --BrowserContextMenuHold._holds == 0) {
      BrowserContextMenuHold._turningOff = null;
      unawaited(
        BrowserContextMenuHold.enableMenu().catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
