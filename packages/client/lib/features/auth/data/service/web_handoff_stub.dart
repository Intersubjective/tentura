import 'handoff_payload.dart';

/// No landing -> app handoff fragment on non-web platforms.
HandoffPayload? readHandoff() => null;

/// No-op off the web.
void scrubHandoff() {}
