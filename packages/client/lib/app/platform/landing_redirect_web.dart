import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

/// Sends the browser to the static landing on the configured public origin.
///
/// Returns `true` when a top-level navigation was initiated.
bool goToLanding({String? invitePath}) {
  if (kQaIntegrationTestMode) return false;
  final target = Uri.parse(kServerName).replace(
    path: invitePath ?? '/invite/',
    queryParameters: const <String, String>{},
    fragment: '',
  );
  web.window.location.assign(target.toString());
  return true;
}
