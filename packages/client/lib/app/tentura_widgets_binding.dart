import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Whether [RenderView.hitTest] should skip [RenderView.child].
///
/// Flutter web can deliver a pointer packet before the first layout. The
/// framework then hit-tests a [RenderSemanticsAnnotations] with `size: MISSING`
/// and asserts (`Cannot hit test a render box that has never been laid out`).
bool shouldSkipUnlaidOutRootChildHitTest(RenderBox? child) =>
    child != null && !child.hasSize;

/// App binding that drops pointer hit-tests until the view child has a size.
///
/// Extends [SentryWidgetsFlutterBinding] so Sentry frame tracking still works
/// when this is constructed before [SentryFlutter.init].
class TenturaWidgetsBinding extends SentryWidgetsFlutterBinding {
  /// Installs this binding if none exists yet.
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      TenturaWidgetsBinding();
      return WidgetsBinding.instance;
    }
  }

  @override
  void hitTestInView(HitTestResult result, Offset position, int viewId) {
    for (final renderView in renderViews) {
      if (renderView.flutterView.viewId != viewId) {
        continue;
      }
      if (shouldSkipUnlaidOutRootChildHitTest(renderView.child)) {
        result.add(HitTestEntry(renderView));
        return;
      }
      break;
    }
    super.hitTestInView(result, position, viewId);
  }
}
