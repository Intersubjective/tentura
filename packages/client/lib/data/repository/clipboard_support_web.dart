import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

bool isClipboardReadSupported() =>
    _navigator.has('clipboard') && _navigator.getProperty('clipboard'.toJS) != null;
