/// No-op on non-web platforms: native platform views don't share a DOM
/// with an accessibility overlay, so there is no hit-test conflict to work
/// around.
void suspendWebSemantics() {}

void resumeWebSemantics() {}

/// Native semantics have no hidden DOM text that can overflow hit bounds.
void clipWebSemanticsLabels(String identifierPrefix) {}
