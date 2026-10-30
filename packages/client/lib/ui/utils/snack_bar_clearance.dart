import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Keeps notice bars clear of a primary action that lives at the bottom of a
/// screen's body rather than in its Scaffold's bottom slot (#406).
///
/// The root Scaffold lays bars out at its own content bottom and knows nothing
/// about such a body-bottom action bar, so the bar was drawn across it (e.g.
/// «Forward to N»). Wrap that action bar in [SnackBarClearance]; while it is
/// mounted, visible and on the current route, `showSnackBar` floats new bars
/// above it. When the action bar appears, grows or shrinks while a bar is up
/// (a composer that comes in after the page loads, a second line typed into
/// it), [snackBarClearanceChanges] tells `showSnackBar` to move that bar
/// (#605).
class SnackBarClearance extends StatefulWidget {
  const SnackBarClearance({required this.child, super.key});

  final Widget child;

  @override
  State<SnackBarClearance> createState() => _SnackBarClearanceState();
}

class _SnackBarClearanceState extends State<SnackBarClearance> {
  static final _mounted = <_SnackBarClearanceState>{};

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _clearanceChanges.notifySoon();
    super.dispose();
  }

  /// Height to keep free, or 0 when this action bar is not showing now
  /// (covered by another route, in an inactive tab, or not laid out).
  double get _clearance {
    if (!mounted) return 0;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return 0;
    if (!TickerMode.valuesOf(context).enabled) return 0;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
    // Laid out but not painted, e.g. the Recipients step kept mounted by the
    // create screen's IndexedStack while Details is shown.
    RenderObject child = box;
    for (var parent = box.parent; parent != null; parent = parent.parent) {
      if (!parent.paintsChild(child)) return 0;
      child = parent;
    }
    return box.size.height;
  }

  @override
  Widget build(BuildContext context) =>
      _ClearanceSizeReporter(child: widget.child);
}

/// Reports a change of the action bar's height (including its first layout)
/// once the frame is drawn.
class _ClearanceSizeReporter extends SingleChildRenderObjectWidget {
  const _ClearanceSizeReporter({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClearanceSizeReporter();
}

class _RenderClearanceSizeReporter extends RenderProxyBox {
  double? _reportedHeight;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height != _reportedHeight) {
      _reportedHeight = size.height;
      _clearanceChanges.notifySoon();
    }
  }
}

class _ClearanceChanges extends ChangeNotifier {
  var _scheduled = false;

  /// Notifies after the current frame: listeners show bars, which must not
  /// happen during layout or while the tree is locked.
  void notifySoon() {
    if (_scheduled || !hasListeners) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        notifyListeners();
      })
      ..ensureVisualUpdate();
  }
}

final _clearanceChanges = _ClearanceChanges();

/// Fires (after the frame) when a [SnackBarClearance] action bar appears,
/// changes height or goes away.
Listenable get snackBarClearanceChanges => _clearanceChanges;

/// Height of the tallest body-bottom action bar showing right now, measured
/// when the bar is shown (so a taller composer, e.g. with the note expanded,
/// is cleared too). 0 when there is none.
double snackBarBottomClearance() {
  var clearance = 0.0;
  for (final state in _SnackBarClearanceState._mounted) {
    final value = state._clearance;
    if (value > clearance) clearance = value;
  }
  return clearance;
}
