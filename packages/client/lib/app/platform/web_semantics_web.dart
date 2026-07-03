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
// A blanket `display: none` on the host (an earlier version of this fix)
// isn't safe either: while semantics is active, Flutter Web swaps in
// SemanticsTextEditingStrategy for focused text fields, which appends the
// *real* editable <input>/<textarea> as a child of the field's own
// <flt-semantics> node (see engine/semantics/text_field.dart) instead of
// the usual always-present, semantics-independent text-editing host.
// `display: none` on an ancestor cannot be overridden by a descendant, so
// hiding the whole host takes that live input out of the DOM along with
// the map-blocking node, breaking typed input into any text field while
// this is in effect (e.g. the location search box).
//
// Overriding `pointer-events` instead is selectively overridable per
// descendant (unlike `display`), so it can neutralize every semantics node
// *except* the one tagged `data-semantics-role="text-field"` — the real
// input surface — which stays interactive. Screen-reader users lose
// semantics for the one screen this is active on, which is an acceptable
// trade-off since panning/tapping a map isn't practically
// screen-reader-navigable anyway.
const _styleElementId = 'tentura-suspend-web-semantics';

web.HTMLStyleElement? _styleElement;

void suspendWebSemantics() {
  if (_styleElement != null) return;
  final style =
      web.document.createElement('style') as web.HTMLStyleElement
        ..id = _styleElementId
        ..textContent =
            'flt-semantics-host, flt-semantics-host * '
            '{ pointer-events: none !important; } '
            'flt-semantics-host [data-semantics-role="text-field"] '
            '{ pointer-events: auto !important; }';
  web.document.head!.appendChild(style);
  _styleElement = style;
}

void resumeWebSemantics() {
  _styleElement?.remove();
  _styleElement = null;
}
