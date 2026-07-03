import 'package:web/web.dart' as web;

// Flutter Web's semantics DOM (`flt-semantics-host`) is layered above
// platform views. Any full-screen route ends up with an ancestor semantics
// node that accepts pointer events across its whole area (needed so screen
// readers can dismiss/traverse the route), which swallows clicks meant for
// a platform view — e.g. Google Maps — beneath it, regardless of the
// view's own (correctly "transparent") semantics config.
//
// This can't be fixed via SemanticsBinding's handle-counting
// (ensureSemantics()/SemanticsHandle.dispose()): on web, disabling the
// framework's tree tells the engine to turn semantics off, but the engine
// echoes that confirmation back through
// PlatformDispatcher.onSemanticsEnabledChanged, which the framework
// interprets as "the platform wants semantics enabled" and reacts by
// creating its own internal SemanticsHandle — one app code never gets a
// reference to and can never dispose. So once semantics has ever been
// enabled (e.g. by App.runner's ensureSemantics() at startup), no number
// of app-level dispose() calls brings the handle count back to zero.
//
// Hiding the DOM host directly sidesteps that entirely: it removes the
// whole semantics subtree from hit-testing (`display: none` takes an
// element and its descendants out of hit-testing regardless of their own
// `pointer-events`), while Flutter keeps generating semantics updates
// against it harmlessly in the background. Screen-reader users lose
// semantics for the one screen this is active on, which is an acceptable
// trade-off since panning/tapping a map isn't practically
// screen-reader-navigable anyway.
String? _previousDisplay;

void suspendWebSemantics() {
  final host = web.document.querySelector('flt-semantics-host');
  if (host == null) return;
  final element = host as web.HTMLElement;
  _previousDisplay = element.style.display;
  element.style.display = 'none';
}

void resumeWebSemantics() {
  final host = web.document.querySelector('flt-semantics-host');
  if (host == null) return;
  (host as web.HTMLElement).style.display = _previousDisplay ?? '';
  _previousDisplay = null;
}
