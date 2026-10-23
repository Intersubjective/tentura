import 'dart:js_interop';

import 'package:web/web.dart' as web;

// With semantics on (the app always turns them on), a press on a semantics
// node that cannot take focus moves the browser focus to the Flutter view.
// The field's real <input>/<textarea> then blurs and the engine stops reading
// it, while Flutter still counts the field as focused, so the next keys go
// nowhere (#624, #688). Cancelling the press's mousedown keeps the browser
// focus where it is; the press still arrives as pointer events and its
// click still arrives as a tap.

final _prefixes = <String>{};
var _listening = false;

/// From now on a mouse press on a semantics node whose identifier starts
/// with one of [semanticsIdentifierPrefixes] leaves the browser focus (and so
/// the text field being typed in) where it is.
void keepTextInputFocusOnPress(Iterable<String> semanticsIdentifierPrefixes) {
  _prefixes.addAll(semanticsIdentifierPrefixes);
  if (_listening || _prefixes.isEmpty) return;
  _listening = true;
  web.document.addEventListener(
    'mousedown',
    _onMouseDown.toJS,
    web.AddEventListenerOptions(capture: true),
  );
}

void _onMouseDown(web.Event event) {
  final target = event.target;
  if (target == null || !target.isA<web.Element>()) return;
  final selector = [
    for (final prefix in _prefixes) '[flt-semantics-identifier^="$prefix"]',
  ].join(',');
  if ((target as web.Element).closest(selector) != null) {
    event.preventDefault();
  }
}

/// Whether the browser focus is on a text input (the focused field's).
bool textInputHasPlatformFocus() {
  final tag = web.document.activeElement?.tagName.toUpperCase();
  return tag == 'INPUT' || tag == 'TEXTAREA';
}
