import 'dart:js_interop';

/// Mirrors the object graph the web map plugin reads during map init.
@JS('google.maps')
external JSObject? get _googleMaps;

/// True when the Google Maps JavaScript API finished loading in the page.
bool isGoogleMapsJsReady() => _googleMaps != null;
