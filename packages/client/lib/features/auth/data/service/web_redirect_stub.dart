/// Off the web there is no static landing to bounce to — native keeps its own
/// login / recovery UI. Returns `false` so callers fall through to that UI.
bool goToLanding({String? invitePath}) => false;
