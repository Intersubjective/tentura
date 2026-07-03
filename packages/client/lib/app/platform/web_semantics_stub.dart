/// No-op on non-web platforms: native platform views don't share a DOM
/// with an accessibility overlay, so there is no hit-test conflict to work
/// around.
void suspendWebSemantics() {}

void resumeWebSemantics() {}
