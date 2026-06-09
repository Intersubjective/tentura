import 'package:google_sign_in/google_sign_in.dart';

import 'package:tentura/env.dart';

/// Native Google sign-in for Settings linking (returns a verified id token).
Future<String?> obtainGoogleIdTokenForLink(Env env) async {
  if (!env.isGoogleNativeLinkConfigured) {
    return null;
  }
  final googleSignIn = GoogleSignIn.instance;
  await googleSignIn.initialize(
    serverClientId: env.googleServerClientId,
    clientId: env.googleIosClientId.isEmpty ? null : env.googleIosClientId,
  );
  if (!googleSignIn.supportsAuthenticate()) {
    return null;
  }
  await googleSignIn.signOut();
  final account = await googleSignIn.authenticate();
  return account.authentication.idToken;
}
