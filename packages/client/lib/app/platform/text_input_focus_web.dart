import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
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
var _semanticsFocusListenerInstalled = false;

/// Repairs a semantics input blurred by the engine while Flutter still gives
/// its EditableText primary focus (button activation or tooltip subtree moves).
///
/// Engine bug (Flutter 3.47.0, #603): a whole-number mouse click on a button
/// counts as an assistive-technology activation and focuses it; the deferred
/// safeBlur then parks focus on flutter-view while EditableText stays focused.
/// Upstream: https://github.com/flutter/flutter/issues/195763
void restoreTextInputFocusAfterSemanticsBlur() {
  if (_semanticsFocusListenerInstalled) return;
  _semanticsFocusListenerInstalled = true;
  final capture = web.AddEventListenerOptions(capture: true);
  web.document
    ..addEventListener('blur', _onBlur.toJS, capture)
    ..addEventListener('focusout', _onFocusOut.toJS, capture);
}

/// The semantics input losing the browser focus while Flutter's primary
/// focus is still its EditableText, and whether the loss is a DOM move of
/// the input (no new focus target, page still focused) rather than a click.
({
  web.HTMLElement input,
  FocusNode focus,
  EditableTextState editable,
  bool moved,
})?
_focusedFieldLosing(web.Event event) {
  final target = event.target;
  if (target == null || !target.isA<web.HTMLElement>()) return null;
  final input = target as web.HTMLElement;
  if (!input.matches(
    'input[data-semantics-role="text-field"],'
    'textarea[data-semantics-role="text-field"]',
  )) {
    return null;
  }
  final focus = FocusManager.instance.primaryFocus;
  final editable = focus?.context?.findAncestorStateOfType<EditableTextState>();
  if (focus == null || editable == null) return null;
  final moved =
      event.isA<web.FocusEvent>() &&
      (event as web.FocusEvent).relatedTarget == null &&
      web.document.hasFocus();
  return (input: input, focus: focus, editable: editable, moved: moved);
}

// A tooltip showing or hiding moves the focused input in the DOM. Captured
// before the input's own blur listener, so the engine keeps editing on it
// and the input gets the focus back before the next key, with no
// reconnection window in which typed keys land on the page.
void _onBlur(web.Event event) {
  final field = _focusedFieldLosing(event);
  if (field == null || !field.moved) return;
  event.stopPropagation();
  final input = field.input;
  Timer.run(() {
    if (input.isConnected &&
        web.document.activeElement != input &&
        identical(FocusManager.instance.primaryFocus, field.focus)) {
      input.focus(web.FocusOptions(preventScroll: true));
    }
  });
}

void _onFocusOut(web.Event event) {
  final field = _focusedFieldLosing(event);
  if (field == null) return;
  final (:input, :focus, :editable, :moved) = field;
  // A semantics subtree move has no new focus target. Do not let the view's
  // bubbling focusout handler mistake it for leaving the app and park Flutter
  // focus on the root scope before the editing connection can be restored.
  if (moved) event.stopPropagation();
  // safeBlur is deferred by the engine. Observe the completed DOM/semantics
  // update, then reopen the editing connection only if logical focus stayed.
  Timer.run(() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!editable.mounted ||
          !identical(FocusManager.instance.primaryFocus, focus) ||
          web.document.activeElement == input) {
        return;
      }
      final scope = focus.enclosingScope;
      focus.unfocus();
      binding
        ..addPostFrameCallback((_) {
          // Navigation or an intentional focus change supersedes this repair.
          if (editable.mounted &&
              focus.context?.mounted == true &&
              focus.canRequestFocus &&
              identical(FocusManager.instance.primaryFocus, scope)) {
            // An internal focus request reopens editing without web's normal
            // select-all-on-focus policy changing the user's caret.
            editable.requestKeyboard();
          }
        })
        ..scheduleFrame();
    });
    binding.scheduleFrame();
  });
}

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
