/// Native platforms have no page focus a click could move off a text field.
void keepTextInputFocusOnPress(Iterable<String> semanticsIdentifierPrefixes) {}

/// Native text input stays with the focused field; nothing moves it on a
/// click elsewhere in the app.
bool textInputHasPlatformFocus() => true;
