import 'package:tentura/consts.dart';

/// Maps hash-routed OAuth returns (`/#/settings/sign-in-methods?linked=…`) and
/// path-based App Links to the Auto Route credentials screen with `linked`.
Uri transformCredentialLinkDeepLink({required Uri uri}) {
  final fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    final normalized = fragment.startsWith('/') ? fragment : '/$fragment';
    if (normalized.startsWith(kPathSignInMethods)) {
      final fragUri = Uri.parse(normalized);
      final linked = fragUri.queryParameters[kQueryCredentialLinked]?.trim();
      if (linked != null && linked.isNotEmpty) {
        return Uri(
          path: kPathSignInMethods,
          queryParameters: {kQueryCredentialLinked: linked},
        );
      }
    }
  }

  final linked = uri.queryParameters[kQueryCredentialLinked]?.trim();
  if (uri.path == kPathSignInMethods && linked != null && linked.isNotEmpty) {
    return uri;
  }

  return uri;
}
